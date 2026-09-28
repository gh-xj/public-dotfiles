#!/usr/bin/env python3
"""Explicit topology checkpoints and opt-in provider resumes; no transcript reads."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

BUILTINS = {
    "claude": {"option": "@claude_sid", "argv": ["claude", "--resume", "{session_id}"]},
    "codex": {"option": "@codex_sid", "argv": ["codex", "resume", "{session_id}"]},
}


def adapters(path):
    result = dict(BUILTINS)
    if path:
        result.update(json.loads(Path(path).read_text()))
    for name, spec in result.items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", name) or not re.fullmatch(r"@[a-z][a-z0-9_]*", spec["option"]):
            raise ValueError("invalid adapter name/option")
        argv = spec["argv"]
        if not isinstance(argv, list) or not argv or not all(isinstance(s, str) and s and "\0" not in s for s in argv):
            raise ValueError("adapter argv must be a nonempty string array")
        if "{session_id}" not in argv:
            raise ValueError("adapter requires a separate {session_id} argument")
    return result


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(f.name, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", help="tmux -L socket name (default: current server)")
    parser.add_argument("--adapters", help="trusted local JSON adapter map; never embedded in a checkpoint")
    sub = parser.add_subparsers(dest="action", required=True)
    save = sub.add_parser("checkpoint")
    save.add_argument("--session", required=True)
    save.add_argument("file")
    restore = sub.add_parser("restore")
    restore.add_argument("file")
    restore.add_argument("--name", help="new session name (default: recovered-<original>)")
    restore.add_argument("--apply", action="store_true", help="create detached session; otherwise print plan")
    restore.add_argument("--resume-agents", action="store_true", help="explicitly launch trusted adapters")
    args = parser.parse_args()
    providers = adapters(args.adapters)
    command = ["tmux"] + (["-L", args.socket] if args.socket else [])
    def tmux(*parts):
        return subprocess.check_output([*command, *parts], text=True).rstrip("\n")
    def field(target, name):
        return tmux("display-message", "-p", "-t", target, "#{" + name + "}")
    if args.action == "checkpoint":
        session = field("=" + args.session, "session_id")
        data = {"version": 1, "name": field(session, "session_name"), "windows": []}
        for wid in tmux("list-windows", "-t", session, "-F", "#{window_id}").splitlines():
            window = {"name": field(wid, "window_name"), "layout": field(wid, "window_layout"), "panes": []}
            for pid in tmux("list-panes", "-t", wid, "-F", "#{pane_id}").splitlines():
                pane = {"cwd": field(pid, "pane_current_path"), "title": field(pid, "pane_title"),
                        "label": field(pid, "@agent_label"), "active": field(pid, "pane_active") == "1"}
                # Prompt cleanup clears session IDs, so plain shells cannot resume stale agents.
                for provider, spec in providers.items():
                    sid = field(pid, spec["option"])
                    if re.fullmatch(r"[A-Za-z0-9_-]{1,128}", sid):
                        pane.update(provider=provider, session_id=sid)
                        break
                window["panes"].append(pane)
            window["active"] = field(wid, "window_active") == "1"
            data["windows"].append(window)
        atomic_json(args.file, data)
        return
    data = json.loads(Path(args.file).read_text())
    if data.get("version") != 1 or not data.get("windows"):
        raise ValueError("unsupported or empty checkpoint")
    name = args.name or "recovered-" + data["name"]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError("restore name must use letters, digits, _ or -")
    # Validate everything before creating anything; refuse missing cwd or adapters.
    for window in data["windows"]:
        if not window.get("panes") or not isinstance(window["name"], str):
            raise ValueError("invalid window")
        for pane in window["panes"]:
            if not Path(pane["cwd"]).is_absolute() or not Path(pane["cwd"]).is_dir():
                raise ValueError("checkpoint working directory is unavailable")
            if pane.get("provider") and args.resume_agents:
                if pane["provider"] not in providers or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", pane.get("session_id", "")):
                    raise ValueError("unknown adapter or invalid session ID")
    if subprocess.run([*command, "has-session", "-t", "=" + name], capture_output=True).returncode == 0:
        raise ValueError("target session exists; choose another --name")
    if not args.apply:
        print(json.dumps({"create_session": name, "windows": len(data["windows"]),
                          "panes": sum(len(w["panes"]) for w in data["windows"]), "resume_agents": args.resume_agents}))
        return
    selected_window = None
    for index, window in enumerate(data["windows"]):
        cwd = window["panes"][0]["cwd"]
        if index == 0:
            pid = tmux("new-session", "-d", "-s", name, "-n", window["name"], "-c", cwd, "-P", "-F", "#{pane_id}")
        else:
            pid = tmux("new-window", "-d", "-t", name + ":", "-n", window["name"], "-c", cwd, "-P", "-F", "#{pane_id}")
        wid = field(pid, "window_id")
        tmux("set-option", "-w", "-t", wid, "automatic-rename", "off")
        active = pid
        for pindex, pane in enumerate(window["panes"]):
            if pindex:
                pid = tmux("split-window", "-d", "-t", wid, "-c", pane["cwd"], "-P", "-F", "#{pane_id}")
                tmux("select-layout", "-t", wid, "tiled")
            tmux("select-pane", "-t", pid, "-T", pane["title"])
            if pane.get("active"):
                active = pid
            if args.resume_agents and pane.get("provider"):
                spec = providers[pane["provider"]]
                argv = [pane["session_id"] if part == "{session_id}" else part for part in spec["argv"]]
                tmux("send-keys", "-t", pid, "-l", shlex.join(argv))
                tmux("send-keys", "-t", pid, "Enter")
        tmux("select-layout", "-t", wid, window["layout"])
        tmux("select-pane", "-t", active)
        if window.get("active"):
            selected_window = wid
    if selected_window:
        tmux("select-window", "-t", selected_window)
    print("restored detached session: " + name)


if __name__ == "__main__":
    main()
