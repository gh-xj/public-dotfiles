#!/usr/bin/env python3
"""Pane-local identity. Cache is private runtime state, never repository data."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unicodedata


def main():
    pane, server = os.getenv("TMUX_PANE", ""), os.getenv("TMUX", "")
    if not server or not re.fullmatch(r"%\d+", pane):
        return
    if len(sys.argv) < 2 or sys.argv[1] not in ("set", "clear"):
        raise SystemExit("usage: agent-pane-title set <label> | clear")
    label = ""
    if sys.argv[1] == "set":
        if len(sys.argv) != 3:
            raise SystemExit("set requires one label")
        label = "".join(c for c in sys.argv[2] if not unicodedata.category(c).startswith("C"))[:80].strip()
    root = Path(os.getenv("XDG_RUNTIME_DIR", str(Path.home() / ".cache"))) / "agent-pane-title"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = hashlib.sha256((server + pane).encode()).hexdigest()
    cache = root / key
    # Serialize statusline and hook writers for this exact server/pane.
    with open(str(cache) + ".lock", "a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            old = json.loads(cache.read_text())
        except (OSError, ValueError):
            old = None
        if old is not None and old["label"] == label:
            return

        def tmux(*args):
            return subprocess.check_output(["tmux", *args], text=True).rstrip("\n")

        if label:
            native = old["native"] if old and old["label"] else tmux("display-message", "-p", "-t", pane, "#{pane_title}")
            tmux("set-option", "-p", "-t", pane, "@agent_label", label)
            tmux("select-pane", "-t", pane, "-T", label)
        else:
            native = ""
            current = tmux("display-message", "-p", "-t", pane, "#{pane_title}")
            tmux("set-option", "-pu", "-t", pane, "@agent_label")
            if old and old["label"] and current == old["label"]:
                tmux("select-pane", "-t", pane, "-T", old["native"])
        cache.write_text(json.dumps({"label": label, "native": native}))
        cache.chmod(0o600)


if __name__ == "__main__":
    main()
