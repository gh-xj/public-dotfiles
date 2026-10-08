#!/usr/bin/env python3
"""Consume documented hook inputs; never inspect agent runtime databases."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    provider, event = sys.argv[1:]
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,31}", provider) or event not in ("start", "end"):
        raise SystemExit("usage: agent-session <provider> start|end")
    pane = os.getenv("TMUX_PANE", "")
    if not os.getenv("TMUX") or not re.fullmatch(r"%\d+", pane):
        return
    data = json.load(sys.stdin)
    if event == "end":
        current = subprocess.check_output(["tmux", "show-option", "-pqv", "-t", pane, "@" + provider + "_sid"], text=True).strip()
        if not data.get("session_id") or current != data["session_id"]:
            return  # A late hook must not clear a newer session in this pane.
        subprocess.run(["agent-pane-title", "clear"], check=True)
        subprocess.run(["tmux", "set-option", "-pu", "-t", pane, "@" + provider + "_sid"], check=True)
        target = subprocess.check_output(["tmux", "show-option", "-pqv", "-t", pane, "@resume_target"], text=True).strip()
        if target == provider + " " + current:
            subprocess.run(["tmux", "set-option", "-pu", "-t", pane, "@resume_target"], check=True)
        return
    # A new session must not inherit any previous provider's ids.
    listed = subprocess.check_output(["tmux", "show-options", "-p", "-t", pane], text=True)
    for option in re.findall(r"^(@[a-z][a-z0-9_]*_sid)\b", listed, re.M):
        subprocess.run(["tmux", "set-option", "-pu", "-t", pane, option], check=True)
    sid = data.get("session_id", "")
    if re.fullmatch(r"[A-Za-z0-9_-]{1,128}", sid):
        subprocess.run(["tmux", "set-option", "-p", "-t", pane, "@" + provider + "_sid", sid], check=True)
        # Prompt hooks clear the *_sid options; recovery resumes from this one.
        subprocess.run(["tmux", "set-option", "-p", "-t", pane, "@resume_target", provider + " " + sid], check=True)
    subprocess.run(["agent-pane-title", "clear"], check=True)
    # Presentation only: never return Claude sessionTitle, which would replace
    # its native first-prompt title. Official statusLine names supersede this.
    cwd = data.get("cwd") or os.getcwd()
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    repo = Path(result.stdout.strip() if result.returncode == 0 else cwd).name or "session"
    subprocess.run(["agent-pane-title", "set", provider.capitalize() + " · " + repo], check=True)


if __name__ == "__main__":
    main()
