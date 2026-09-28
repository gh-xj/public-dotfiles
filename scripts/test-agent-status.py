#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
claude = json.loads((repo / "config/claude/settings.json").read_text())
assert "refreshInterval" not in claude["statusLine"]
for config in (claude, json.loads((repo / "config/codex/hooks.json").read_text())):
    post = config["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
    assert post == "agent-workmux-status resume"
with tempfile.TemporaryDirectory(prefix="agent-status-") as tmp:
    root = Path(tmp)
    log = root / "calls"
    fake = root / "workmux"
    fake.write_text('#!/bin/sh\nprintf "%s\\n" "$2" >> "$STATUS_TEST_LOG"\n')
    fake.chmod(0o700)
    env = dict(os.environ, PATH=tmp + ":" + os.environ["PATH"], XDG_RUNTIME_DIR=tmp,
               TMUX="/tmp/test,123,0", TMUX_PANE="%2", STATUS_TEST_LOG=str(log))
    def run(event, overrides=None):
        subprocess.run(["bash", str(repo / "scripts/agent-workmux-status.sh"), event],
                       env=dict(env, **(overrides or {})), check=True)
    for _ in range(30):
        run("resume")
    assert not log.exists(), "tool results must not invoke Workmux without a pending wait"
    run("working")
    run("waiting")
    run("resume", {"TMUX_PANE": "%3"})
    assert log.read_text().splitlines() == ["working", "waiting"]
    run("resume")
    run("resume")
    run("done")
    run("working", {"TMUX": ""})
    assert log.read_text().splitlines() == ["working", "waiting", "working", "done"]
print("event-driven statusline and bounded Workmux transitions verified")
