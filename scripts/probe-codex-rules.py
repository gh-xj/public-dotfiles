#!/usr/bin/env python3
"""Drive the real CLI against a loopback fixture model; only harmless marker programs execute."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import threading


CASES = [
    ("root-delete", "rm", ["-rf", "/"], "forbidden"),
    ("force-push", "git", ["push", "--force"], "prompt"),
    ("force-push-short", "git", ["push", "-f"], "prompt"),
    ("hard-reset", "git", ["reset", "--hard"], "prompt"),
    ("clean-worktree", "git", ["clean", "-fd"], "prompt"),
]


def probe(root, case, decision, bypass, codex):
    name, tool, prefix, _ = case
    mode = "bypass" if bypass else "never"
    work = root / (mode + "-" + name + "-" + decision)
    work.mkdir()
    runtime = work / "codex-home"
    (runtime / "rules").mkdir(parents=True)
    marker = work / "executed"
    (work / "bin").mkdir()
    executable = work / "bin" / tool
    # The model only requests this absolute inert executable. It cannot reach
    # real rm/git even if the policy under test completely fails open.
    executable.write_text('#!/bin/sh\nprintf executed > ' + shlex.quote(str(marker)) + '\n')
    executable.chmod(0o700)
    subprocess.run(["git", "-c", "init.templateDir=", "init", "-q", str(work)], check=True)
    pattern = [[tool, str(executable)], *prefix]
    (runtime / "rules/default.rules").write_text('prefix_rule(pattern=' + json.dumps(pattern) + ', decision=' + json.dumps(decision) + ')\n')
    observed = {"requests": 0, "tools": [], "tool_outputs": []}
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            observed["requests"] += 1
            observed["tools"] = [tool.get("name", tool.get("type")) for tool in request.get("tools", [])]
            for item in request.get("input", []):
                if isinstance(item, dict) and item.get("type") == "function_call_output":
                    observed["tool_outputs"].append(item.get("output"))
            sequence = str(observed["requests"])
            running = re.search(r"session ID (\d+)", str(observed["tool_outputs"][-1])) if observed["tool_outputs"] else None
            if observed["requests"] == 1:
                item = {"id": "fc_" + sequence, "type": "function_call", "call_id": "call_" + sequence, "name": "exec_command",
                        "arguments": json.dumps({"cmd": shlex.join([str(executable), *prefix]), "workdir": str(work),
                                                 "shell": "/bin/bash", "login": False, "yield_time_ms": 10000})}
            elif running and observed["requests"] < 15:
                item = {"id": "fc_" + sequence, "type": "function_call", "call_id": "call_" + sequence, "name": "write_stdin",
                        "arguments": json.dumps({"session_id": int(running[1]), "chars": "", "yield_time_ms": 1000})}
            else:
                item = {"id": "msg_probe", "type": "message", "role": "assistant", "status": "completed",
                        "content": [{"type": "output_text", "text": "Probe complete.", "annotations": []}]}
            events = [("response.created", {"response": {"id": "resp_probe", "status": "in_progress", "output": []}}),
                      ("response.output_item.done", {"output_index": 0, "item": item}),
                      ("response.completed", {"response": {"id": "resp_probe", "status": "completed", "output": [item],
                                                           "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}})]
            payload = "".join("event: " + kind + "\ndata: " + json.dumps(dict(type=kind, **value)) + "\n\n" for kind, value in events).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    config = f'''model = "gpt-5.4"
model_provider = "fixture"
approval_policy = "never"
sandbox_mode = "danger-full-access"
model_reasoning_effort = "low"
[model_providers.fixture]
name = "Local fixture"
base_url = "http://127.0.0.1:{server.server_port}/v1"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 0
stream_max_retries = 0
[features]
hooks = false
shell_snapshot = false
'''
    (runtime / "config.toml").write_text(config)
    try:
        completed = subprocess.run([codex, "exec", "--ephemeral", "--json", "--skip-git-repo-check", *(["--dangerously-bypass-approvals-and-sandbox"] if bypass else []), "Run the fixture tool once."],
                                   cwd=work, env=dict(os.environ, CODEX_HOME=str(runtime)), stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=60)
        (work / "cli.stdout").write_text(completed.stdout)
        (work / "cli.stderr").write_text(completed.stderr)
    finally:
        server.shutdown()
        server.server_close()
    outputs = json.dumps(observed["tool_outputs"])
    rejection = ("policy forbids" in outputs) if decision == "forbidden" else ("approval required by policy" in outputs and "Never" in outputs) if decision == "prompt" else False
    passed = completed.returncode == 0 and observed["requests"] >= 2 and "exec_command" in observed["tools"] and (marker.exists() if decision == "allow" else not marker.exists() and rejection)
    result = {"case": name, "mode": mode, "decision": decision, "marker_created": marker.exists(), "policy_rejection": rejection, "passed": passed}
    (work / "evidence.json").write_text(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.output or Path(tempfile.mkdtemp(prefix="codex-rule-proof-"))
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    binary = shutil.which("codex")
    if not binary:
        raise SystemExit("official Codex CLI is required")
    codex = str(Path(binary).resolve())
    version = subprocess.check_output([codex, "--version"], text=True).strip()
    rules = Path(__file__).resolve().parent.parent / ".codex/rules/default.rules"
    for name, tool, prefix, decision in CASES:
        classified = json.loads(subprocess.check_output([codex, "execpolicy", "check", "--rules", str(rules), "--", tool, *prefix], text=True))
        if classified.get("decision") != decision:
            raise SystemExit("published prefix classification failed: " + name)
    results = []
    for bypass in (False, True):
        for case in CASES:
            for decision in ("allow", case[3]):
                result = probe(root, case, decision, bypass, codex)
                results.append(result)
                print(json.dumps(result), flush=True)
    (root / "summary.json").write_text(json.dumps({"version": version, "results": results}, indent=2))
    print("evidence directory:", root)
    if not all(result["passed"] for result in results):
        raise SystemExit("runtime rule enforcement not proven; do not ship these decisions")


if __name__ == "__main__":
    main()
