#!/usr/bin/env python3
"""Contract tests against real tmux and the generated, pinned Workmux binary."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

socket, binaries = sys.argv[1:]
repo = Path(__file__).resolve().parent.parent


def tmux(*args):
    return subprocess.check_output(["tmux", "-L", socket, *args], text=True).strip()


with tempfile.TemporaryDirectory(prefix="pane-contract-") as tmp:
    p1 = tmux("display-message", "-p", "#{pane_id}")
    p2 = tmux("split-window", "-d", "-P", "-F", "#{pane_id}", "-t", p1, "sleep 120")
    before = tmux("display-message", "-p", "-t", p1, "#{window_name}")
    base = dict(os.environ, HOME=tmp, XDG_RUNTIME_DIR=tmp, XDG_CONFIG_HOME=tmp + "/config", XDG_STATE_HOME=tmp + "/state",
                PATH=binaries + ":" + os.environ["PATH"], TMUX=tmux("display-message", "-p", "#{socket_path},#{pid},0"))
    for key in list(base):
        if key.startswith("WORKMUX_"):
            del base[key]
    config = Path(tmp) / "config/workmux"
    config.mkdir(parents=True)
    (config / "config.yaml").write_text("status_format: false\n")
    def run(pane, command, data=None):
        return subprocess.run(command, env=dict(base, TMUX_PANE=pane), input=json.dumps(data) if data is not None else None,
                              text=True, capture_output=True, check=True)
    def value(pane, fmt):
        return tmux("display-message", "-p", "-t", pane, fmt)
    run("", ["agent-pane-title", "set", "outside"])
    tmux("select-pane", "-t", p1, "-T", "shell")
    fixtures = [({"session_name": "auth-refactor", "agent": {"name": "reviewer"}}, "Claude/reviewer · auth-refactor"),
                ({"session_name": "renamed"}, "Claude · renamed"),
                ({"agent": {"name": "reviewer"}}, "Claude/reviewer"), ({}, "")]
    for data, expected in fixtures:
        run(p1, ["bash", str(repo / ".claude/statusline-command.sh")], data)
        assert value(p1, "#{@agent_label}") == expected
    assert value(p1, "#{pane_title}") == "shell"
    run(p1, ["agent-pane-title", "set", "Claude/reviewer · auth-refactor"])
    run(p2, ["agent-session", "codex", "start"], {"session_id": "test-session", "cwd": str(repo), "model": "test"})
    assert value(p2, "#{@agent_label}").startswith("Codex · ")
    assert value(p2, "#{@codex_sid}") == "test-session"
    run(p2, ["agent-pane-title", "set", "Codex · investigate flaky tests"])
    # The cache must bypass tmux entirely on an unchanged value.
    fake = Path(tmp) / "bin"
    fake.mkdir()
    (fake / "tmux").write_text("#!/bin/sh\nexit 99\n")
    (fake / "tmux").chmod(0o700)
    subprocess.run([sys.executable, str(repo / "scripts/agent-pane-title.py"), "set", "Codex · investigate flaky tests"],
                   env=dict(base, TMUX_PANE=p2, PATH=str(fake) + ":" + base["PATH"]), check=True)
    run(p1, ["workmux", "set-window-status", "working"])
    first = value(p1, "#{@workmux_pane_status}")
    assert first
    for state in ("waiting", "done"):
        run(p2, ["workmux", "set-window-status", state])
        assert value(p2, "#{@workmux_pane_status}") and value(p2, "#{@workmux_pane_status}") != first
        assert value(p1, "#{@workmux_pane_status}") == first
    border = tmux("show-options", "-gv", "pane-border-format")
    assert value(p1, border) != value(p2, border)
    assert "Claude/reviewer" in value(p1, border) and "Codex" in value(p2, border)
    tmux("set-hook", "-R", "-t", p2, "pane-focus-in")
    assert not value(p2, "#{@workmux_pane_status}")
    assert value(p1, "#{@workmux_pane_status}") == first
    run(p2, ["workmux", "set-window-status", "done"])
    run(p2, ["workmux", "set-window-status", "clear"])
    assert not value(p2, "#{@workmux_pane_status}")
    assert value(p1, "#{@workmux_pane_status}") == first
    assert value(p1, "#{window_name}") == before
    run(p2, ["agent-pane-title", "set", "a\n\x1bb" + "界" * 100])
    label = value(p2, "#{@agent_label}")
    assert len(label) <= 80 and "\x1b" not in label and "\n" not in label
    run(p2, ["agent-session", "codex", "end"], {})
    assert not value(p2, "#{@agent_label}") and not value(p2, "#{@codex_sid}")
    tmux("select-pane", "-t", p2, "-T", "nvim")
    assert "nvim" in value(p2, border)
    tmux("kill-pane", "-t", p2)
print("pane labels, Claude rename fixtures, Codex hooks, native fallback and Workmux contract passed")
