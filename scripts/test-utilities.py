#!/usr/bin/env python3
"""Disposable fixtures only; no real checkpoints, agents or editor processes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

scripts = Path(__file__).resolve().parent


def run(name, *args, ok=True):
    result = subprocess.run([sys.executable, str(scripts / (name + ".py")), *map(str, args)], capture_output=True, text=True)
    if ok:
        assert result.returncode == 0, result.stderr
    else:
        assert result.returncode != 0
    return result.stdout


with tempfile.TemporaryDirectory(prefix="public-utilities-") as tmp:
    root = Path(tmp) / "scratch"
    created = Path(run("scratch-gc", "--root", root, "new", "test", "--purpose", "fixture").strip())
    outside = Path(tmp) / "preserve"
    outside.mkdir()
    (outside / "evidence").write_text("keep")
    (root / "symlink").symlink_to(outside, target_is_directory=True)
    unmanaged = root / "unmanaged"
    unmanaged.mkdir()
    data = json.loads((created / "manifest.json").read_text())
    data.update(created_at=time.time() - 7200, expires_at=time.time() - 3600)
    (created / "manifest.json").write_text(json.dumps(data))
    dry = run("scratch-gc", "--root", root, "collect")
    assert "would-quarantine" in dry and created.exists()
    result = run("scratch-gc", "--root", root, "collect", "--apply")
    assert not created.exists() and "recover_from" in result
    assert (outside / "evidence").read_text() == "keep" and unmanaged.exists()
    assert list((root / ".quarantine").glob("*/manifest.json"))
    run("scratch-gc", "--root", root, "new", "../bad", "--purpose", "fixture", ok=False)
    run("scratch-gc", "--root", root, "new", "test", "--purpose", "fixture", "--ttl-hours", "-1", ok=False)

    socket = "recovery-test-" + str(os.getpid())
    def tmux(*args):
        return subprocess.check_output(["tmux", "-L", socket, *args], text=True).strip()
    try:
        p1 = tmux("-f", "/dev/null", "new-session", "-d", "-s", "fixture", "-n", "durable", "-c", tmp, "-P", "-F", "#{pane_id}", "sleep 120")
        p2 = tmux("split-window", "-d", "-h", "-t", p1, "-c", tmp, "-P", "-F", "#{pane_id}", "sleep 120")
        tmux("set-option", "-p", "-t", p1, "@claude_sid", "public-test-id")
        tmux("select-pane", "-t", p1, "-T", "Reviewer")
        tmux("select-pane", "-t", p2, "-T", "Shell")
        checkpoint = Path(tmp) / "checkpoint.json"
        run("tmux-recovery", "--socket", socket, "checkpoint", "--session", "fixture", checkpoint)
        saved = json.loads(checkpoint.read_text())
        assert len(saved["windows"][0]["panes"]) == 2
        assert saved["windows"][0]["panes"][0]["provider"] == "claude"
        assert checkpoint.stat().st_mode & 0o077 == 0
        run("tmux-recovery", "--socket", socket, "restore", checkpoint)
        assert tmux("list-sessions", "-F", "#{session_name}") == "fixture"
        run("tmux-recovery", "--socket", socket, "restore", checkpoint, "--apply")
        assert tmux("list-panes", "-t", "recovered-fixture:", "-F", "#{pane_id}").count("\n") == 1
        assert tmux("list-windows", "-t", "recovered-fixture", "-F", "#{window_name}") == "durable"
        # Idempotence means refusing collisions, never deleting a user's session.
        run("tmux-recovery", "--socket", socket, "restore", checkpoint, "--apply", ok=False)
        adapter = Path(tmp) / "adapters.json"
        adapter.write_text(json.dumps({"claude": {"option": "@claude_sid", "argv": ["printf", "%s", "{session_id}"]}}))
        run("tmux-recovery", "--socket", socket, "--adapters", adapter, "restore", checkpoint, "--name", "adapter-test", "--apply", "--resume-agents")
        assert tmux("has-session", "-t", "=adapter-test") == ""
    finally:
        subprocess.run(["tmux", "-L", socket, "kill-server"], capture_output=True)
print("scratch ownership/TTL/quarantine and detached tmux restore/adapter tests passed")
