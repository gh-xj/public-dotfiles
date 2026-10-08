#!/usr/bin/env python3
import copy
import importlib.util
import json
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("recovery", repo / "scripts/tmux-recovery.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

with tempfile.TemporaryDirectory(prefix="recovery-fixture-") as tmp:
    root = Path(tmp).resolve()
    socket = "public-recovery-test-" + str(os.getpid())
    engine = r.Engine(r.adapters(), socket)
    def tmux(*args):
        return engine.tmux(*args)
    def rejected(callback):
        try:
            callback()
        except (ValueError, RuntimeError):
            return
        raise AssertionError("unsafe operation was accepted")
    try:
        subprocess.run(["tmux", "-L", socket, "-f", "/dev/null", "new-session", "-d", "-s", "project one", "-c", str(root),
                        "-x", "180", "-y", "70", "sleep", "120"], env=dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache")), check=True)
        tmux("set-option", "-g", "default-shell", "/bin/bash")
        tmux("set-option", "-g", "automatic-rename", "off")
        tmux("move-window", "-s", "project one:0", "-t", "project one:3")
        tmux("rename-window", "-t", "project one:3", "durable work")
        p1 = engine.field("project one:3", "pane_id")
        p2 = tmux("split-window", "-d", "-h", "-t", p1, "-c", root, "-P", "-F", "#{pane_id}", "sleep", "120")
        tmux("select-pane", "-t", p1, "-T", "Reviewer")
        tmux("set-option", "-p", "-t", p1, "@agent_label", "Claude/reviewer")
        tmux("set-option", "-p", "-t", p1, "@claude_sid", "claude-test-1")
        tmux("select-pane", "-t", p2, "-T", "title $(touch SHOULD_NOT_EXIST)")
        tmux("set-option", "-p", "-t", p2, "@agent_label", "Codex/test")
        tmux("set-option", "-p", "-t", p2, "@codex_sid", "codex-test-1")
        tmux("select-pane", "-t", p2)
        docpane = tmux("new-window", "-d", "-t", "project one:7", "-n", "documents", "-c", root, "-P", "-F", "#{pane_id}", "sleep", "120")
        tmux("select-pane", "-t", docpane, "-T", "Documents")
        document = root / "document $(touch NEVER).md"
        document.write_text("# Recovery fixture\n")
        tmux("set-option", "-p", "-t", docpane, r.DOCUMENT, document)
        tmux("select-window", "-t", "project one:3")
        tmux("new-session", "-d", "-s", "second/session", "-c", root, "sleep", "120")
        tmux("select-pane", "-t", "second/session:0", "-T", "Second")
        payload = engine.capture()
        assert engine.capture("project one")["sessions"][0]["name"] == "project one"
        assert len(payload["sessions"]) == 2
        assert [w["index"] for w in payload["sessions"][0]["windows"]] == [3, 7]
        state = root / "state"
        saved = r.save(state, "all", payload, 3, 7)
        path = Path(saved["file"])
        assert path.stat().st_mode & 0o777 == 0o600
        # Legal JSON with a wrong envelope must not block future checkpoints.
        unknown = []
        for i, invalid in enumerate(([], None, 42, "text", {"format": r.FORMAT})):
            broken = state / (r.PREFIX + "broken-" + str(i) + ".json")
            broken.write_text(json.dumps(invalid))
            unknown.append((broken, broken.read_bytes()))
        assert not r.save(state, "all", payload, 1, 7)["changed"]
        before_files = {p.name: p.read_bytes() for p in state.iterdir()}
        bad = copy.deepcopy(payload)
        bad["sessions"][0]["windows"][0]["panes"][0]["title"] = "x" * 4097
        rejected(lambda: r.save(state, "all", bad, 1, 7))
        assert before_files == {p.name: p.read_bytes() for p in state.iterdir()}
        for broken, contents in unknown:
            assert broken.read_bytes() == contents
            broken.unlink()  # Fixture cleanup, never engine retention.
        first_mtime = path.stat().st_mtime_ns
        same = r.save(state, "all", engine.capture(), 3, 7)
        assert not same["changed"] and path.stat().st_mtime_ns == first_mtime
        cli = subprocess.run([sys.executable, str(repo / "scripts/tmux-recovery.py"), "--socket", socket,
                              "--output-directory", str(state), "checkpoint", "--session", "project one"], capture_output=True, text=True, check=True)
        single = Path(json.loads(cli.stdout)["file"])
        assert single.parent == state and "project one" not in single.name
        assert r.read_record(single)["payload"]["sessions"][0]["name"] == "project one"
        assert not (root / "SHOULD_NOT_EXIST").exists()
        legacy = state / "legacy.json"
        legacy.write_text("preserve unknown history")
        for i in range(5):
            variant = copy.deepcopy(payload)
            variant["sessions"][0]["windows"][0]["panes"][0]["label"] = str(i)
            r.save(state, "all", variant, 3, 7)
        assert len(list(state.glob(r.PREFIX + "*.json"))) == 3
        assert legacy.read_text() == "preserve unknown history"
        # Age pruning is independent of mtime. Only verified engine-owned names
        # and checksums participate; the current unchanged snapshot is protected.
        aged = {"format": r.FORMAT, "version": 1, "scope": "all", "created_ns": 1, "payload": payload, "sha256": r.digest(payload)}
        aged_path = state / r.filename(aged)
        aged_path.write_text(json.dumps(aged))
        r.save(state, "all", payload, 3, 1)
        assert not aged_path.exists()

        # Existing sessions are skipped, never replaced or failed.
        collide = engine.restore(payload, apply=True)
        assert [x["reason"] for x in collide["skipped"]] == ["exists", "exists"] and not collide["restored"]
        before = tmux("list-sessions", "-F", "#{session_name}")
        plan = engine.restore(payload, prefix="restored-")
        assert plan["mode"] == "plan" and before == tmux("list-sessions", "-F", "#{session_name}")
        # One missing directory falls back to ~; one corrupt session fails alone.
        bad = copy.deepcopy(payload)
        bad["sessions"][0]["windows"][0]["panes"][0]["cwd"] = str(root / "missing")
        bad["sessions"][1]["windows"][0]["panes"][0]["providers"] = {"claude": {"option": "@claude_sid", "session_id": "x;touch BAD"}}
        outcome = engine.restore(bad, apply=True, prefix="bad-")
        assert outcome["restored"] == ["bad-project one"] and outcome["cwd_fallbacks"] == 1
        assert [f["session"] for f in outcome["failed"]] == ["bad-second/session"] and not engine.exists("bad-second/session")
        assert engine.field("bad-project one:3.0", "pane_current_path") == str(Path.home().resolve()) or engine.field("bad-project one:3.0", "pane_current_path")
        assert not (root / "BAD").exists()
        engine.restore(payload, apply=True, prefix="restored-")
        restored = engine.capture("restored-project one")["sessions"][0]
        assert [w["index"] for w in restored["windows"]] == [3, 7]
        assert [w["name"] for w in restored["windows"]] == ["durable work", "documents"]
        assert restored["windows"][0]["active"]
        panes = restored["windows"][0]["panes"]
        assert [p["label"] for p in panes] == ["Claude/reviewer", "Codex/test"]
        assert panes[1]["active"] and panes[1]["title"] == "title $(touch SHOULD_NOT_EXIST)"
        assert panes[0]["providers"]["claude"]["session_id"] == "claude-test-1"
        assert tmux("show-option", "-pqv", "-t", engine.field("restored-project one:3.0", "pane_id"), r.RESUME) == "claude claude-test-1"
        assert restored["windows"][1]["panes"][0]["document"] == str(document)
        import re
        shape = lambda layout: re.sub(r'(\d+x\d+,\d+,\d+),\d+', r'\1,P', layout.split(',', 1)[1])
        assert shape(restored["windows"][0]["layout"]) == shape(payload["sessions"][0]["windows"][0]["layout"])
        assert not (root / "SHOULD_NOT_EXIST").exists()

        extra_pane = tmux("split-window", "-d", "-h", "-t", "restored-project one:3", "-c", root, "-P", "-F", "#{pane_id}", "sleep", "120")
        tmux("set-option", "-p", "-t", extra_pane, "@agent_label", "Third")
        tmux("select-pane", "-t", extra_pane, "-T", "Third")
        first_pane = tmux("list-panes", "-t", "restored-project one:3", "-F", "#{pane_id}").splitlines()[0]
        tmux("select-layout", "-t", "restored-project one:3", "main-vertical")
        tmux("swap-pane", "-s", first_pane, "-t", extra_pane)
        geometry = "#{@agent_label}:#{pane_index}:#{pane_left},#{pane_top},#{pane_width},#{pane_height}"
        before_geometry = tmux("list-panes", "-t", "restored-project one:3", "-F", geometry)
        engine.restore(engine.capture("restored-project one"), apply=True, prefix="permuted-")
        assert before_geometry == tmux("list-panes", "-t", "permuted-restored-project one:3", "-F", geometry)

        # A pane with garbage metadata loses only that metadata, never the checkpoint.
        tmux("set-option", "-p", "-t", p1, "@claude_sid", "bad;id")
        noisy = r.Engine(r.adapters(), socket)
        tolerant = noisy.capture("project one")
        assert tolerant["sessions"][0]["windows"][0]["panes"][0]["providers"] == {} and any("invalid claude id" in w for w in noisy.warnings)
        tmux("set-option", "-p", "-t", p1, "@claude_sid", "claude-test-1")
        r.log_run(state, "fixture run")
        assert (state / "recovery.log").read_text().rstrip().endswith("fixture run")
        health = r.status(state)
        assert health["invalid"] == [] and health["valid"] >= 1 and health["last_run"].endswith("fixture run")
        newest = max(state.glob(r.PREFIX + "*.json"))
        broken = state / (r.PREFIX + "all-1-deadbeefdead.json")
        broken.write_text(newest.read_text().replace('"sha256"', '"sha256": "0", "x"', 1))
        assert r.status(state)["invalid"] == [broken.name], "a corrupt checkpoint is named, not hidden"
        broken.unlink()

        # An override is trusted argv, while checkpoint IDs remain separate data.
        marker = root / "adapter-ran"
        writer = root / "writer.py"
        writer.write_text("import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(sys.argv[2])\n")
        adapter = root / "adapters.json"
        adapter.write_text(json.dumps({"codex": {"option": "@codex_sid", "argv": [sys.executable, str(writer), str(marker), "{session_id}"]}}))
        custom = r.Engine(r.adapters(adapter), socket)
        only = {"sessions": [copy.deepcopy(payload["sessions"][0])]}
        only["sessions"][0]["windows"] = [only["sessions"][0]["windows"][0]]
        only["sessions"][0]["windows"][0]["panes"] = [only["sessions"][0]["windows"][0]["panes"][1]]
        only["sessions"][0]["windows"][0]["layout"] = engine.field("second/session:0", "window_layout")
        assert custom.restore(only, apply=True, prefix="adapter-")["restored"] == ["adapter-project one"]
        parked_pane = custom.field("adapter-project one:3", "pane_id")
        assert not marker.exists(), "restore must start nothing"
        assert custom.resume(current=parked_pane)["started"] == [parked_pane]
        for _ in range(50):
            if marker.exists(): break
            time.sleep(0.02)
        assert marker.read_text() == "codex-test-1"
        assert custom.exists("adapter-project one"), "exited resumed command must leave visible recovery state"
        # A pane at a plain shell prompt gets the command typed; a busy pane is skipped.
        shell_pane = tmux("new-window", "-d", "-t", "project one:9", "-c", root, "-P", "-F", "#{pane_id}", "bash", "--norc", "--noprofile")
        marker.unlink()
        tmux("set-option", "-p", "-t", shell_pane, r.RESUME, "codex codex-test-2")
        tmux("set-option", "-p", "-t", p1, r.RESUME, "codex codex-test-3")
        time.sleep(0.3)
        assert custom.resume(current=p1)["skipped"] == [{"pane": p1, "reason": "not at a shell prompt"}]
        done = custom.resume(current=shell_pane)
        assert done["started"] == [shell_pane]
        for _ in range(50):
            if marker.exists(): break
            time.sleep(0.02)
        assert marker.read_text() == "codex-test-2"
        tmux("set-option", "-pu", "-t", p1, r.RESUME)
        # Editors are found anywhere in a pane's process tree and report unsaved buffers.
        draft = root / "draft.md"
        draft.write_text("saved\n")
        editor_pane = tmux("new-window", "-d", "-t", "project one:10", "-c", root, "-P", "-F", "#{pane_id}", "bash", "-c", f"nvim --clean {shlex.quote(str(draft))}; sleep 1")
        for _ in range(100):
            if any(d for d, _ in r.editors(r.process_table(), r.subtree(r.process_table(), int(engine.field(editor_pane, "pane_pid"))))): break
            time.sleep(0.05)
        tmux("send-keys", "-t", editor_pane, "ihello", "Escape")
        time.sleep(0.5)
        seen = [p for w in engine.capture("project one")["sessions"][0]["windows"] for p in w["panes"] if p.get("document") == str(draft.resolve())]
        assert seen, "editor launched under a wrapper must be recorded"
        assert any(e["document"] == str(draft.resolve()) for e in engine.preflight()["editors_unsaved"])
        assert Path(engine.preflight(root / "lag")["bundle"]).read_text().startswith("## uptime")
        tmux("kill-window", "-t", editor_pane)
        tmux("kill-window", "-t", shell_pane)
        # Orphans: ppid-1 processes carrying this server's TMUX and a dead pane id.
        dead = subprocess.Popen(["sh", "-c", "sleep 60 >/dev/null 2>&1 & echo $!"], env=dict(os.environ, TMUX=engine.field(p1, "socket_path") + ",1,0", TMUX_PANE="%99999"),
                                stdout=subprocess.PIPE, text=True)
        ghost = int(dead.communicate()[0])
        for _ in range(50):
            if any(o["pid"] == ghost for o in engine.orphans()): break
            time.sleep(0.05)
        assert any(o["pid"] == ghost and o["pane"] == "%99999" for o in engine.orphans())
        os.kill(ghost, 15)
        documents = {"sessions": [copy.deepcopy(payload["sessions"][0])]}
        documents["sessions"][0]["windows"] = [documents["sessions"][0]["windows"][1]]
        documents["sessions"][0]["windows"][0]["active"] = True
        engine.restore(documents, apply=True, prefix="document-")
        doc_pane = engine.field("document-project one:7", "pane_id")
        assert engine.resume(current=doc_pane)["started"] == [doc_pane]
        for _ in range(50):
            if engine.field("document-project one:7", "pane_current_command") == "nvim": break
            time.sleep(0.02)
        assert engine.field("document-project one:7", "pane_current_command") == "nvim"
        assert not (root / "NEVER").exists()
        env = dict(os.environ, TMUX=engine.field(p1, "socket_path") + "," + engine.field(p1, "pid") + ",0", TMUX_PANE=p1, EDITOR="/usr/bin/true")
        subprocess.run(["task", "--taskfile", str(repo / "global/Taskfile.yml"), "new-human-req-doc", "--", "--name", "Recovery fixture"], cwd=root, env=env, check=True, capture_output=True)
        assert Path(engine.field(p1, r.DOCUMENT)).is_file()
        # Any provider name maps to @<provider>_sid; a start clears every other *_sid.
        fakebin = root / "bin"
        fakebin.mkdir()
        (fakebin / "agent-pane-title").write_text("#!/bin/sh\nexit 0\n")
        (fakebin / "agent-pane-title").chmod(0o700)
        hook = lambda provider, event, sid: subprocess.run([sys.executable, str(repo / "scripts/agent-session.py"), provider, event], input=json.dumps({"session_id": sid, "cwd": str(root)}),
                                                           env=dict(env, PATH=f"{fakebin}:{os.environ['PATH']}"), text=True, check=True)
        option = lambda name: tmux("show-option", "-pqv", "-t", p1, name)
        tmux("set-option", "-p", "-t", p1, "@codex_sid", "stale-1")
        hook("gemini", "start", "gemini-1")
        assert (option("@gemini_sid"), option("@codex_sid"), option(r.RESUME)) == ("gemini-1", "", "gemini gemini-1")
        hook("gemini", "end", "gemini-1")
        assert option("@gemini_sid") == "" and option(r.RESUME) == ""
        toml = root / "adapters.toml"
        toml.write_text('[adapters.custom]\noption="@custom_sid"\nargv=["custom-cli","resume","{session_id}"]\n')
        assert "custom" in r.adapters(toml)
        adapter.write_text(json.dumps({"codex": {"option": "@codex_sid", "argv": ["tool", "resume {session_id}"]}}))
        rejected(lambda: r.adapters(adapter))

        # Failure during construction does not roll back by deleting sessions.
        partial = r.Engine(r.adapters(), socket)
        original = partial.tmux
        def fail_new_window(*args):
            if args[0] == "new-window": raise RuntimeError("fixture failure")
            return original(*args)
        partial.tmux = fail_new_window
        outcome = partial.restore(payload, apply=True, prefix="partial-")
        assert [f["session"] for f in outcome["failed"]] == ["partial-project one"]
        assert outcome["restored"] == ["partial-second/session"], "one failed session must not cost the next"
        assert partial.exists("partial-project one") and engine.exists("project one")
    finally:
        subprocess.run(["tmux", "-L", socket, "kill-server"], capture_output=True)
print("multi-session recovery, tolerance, resume, editors, orphans, retention and adapter fixtures passed")
