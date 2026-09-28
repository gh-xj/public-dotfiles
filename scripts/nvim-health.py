#!/usr/bin/env python3
"""Report same-user orphan embedded Neovim instances; termination is interactive."""
import argparse
import os
from pathlib import Path
import shlex
import signal
import subprocess


def candidate(line):
    fields = line.strip().split(None, 5)
    if len(fields) != 6:
        return None
    pid, ppid, uid, tty, executable, args = fields
    try:
        argv = shlex.split(args)
        if int(ppid) != 1 or int(uid) != os.getuid() or tty not in ("??", "?"):
            return None
        if Path(executable).name != "nvim" or not argv or Path(argv[0]).name != "nvim" or "--embed" not in argv[1:]:
            return None
        return int(pid)
    except (ValueError, IndexError):
        return None


def records():
    out = subprocess.check_output(["ps", "-axo", "pid=,ppid=,uid=,tty=,comm=,args="], text=True)
    return {pid: line for line in out.splitlines() if (pid := candidate(line)) is not None}


def identity(pid):
    return subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kill", action="store_true", help="confirm each validated orphan using a terminal")
    args = parser.parse_args()
    found = records()
    for pid, line in found.items():
        print(line.strip())
    if not found:
        print("No orphan nvim --embed processes found.")
    if args.kill:
        if not os.isatty(0) or not os.isatty(1):
            raise SystemExit("--kill requires an interactive terminal")
        for pid in found:
            started = identity(pid)
            answer = input(f"Send SIGTERM to orphan {pid}? Type its PID: ")
            if answer != str(pid):
                continue
            # Revalidate parent, owner, executable, arguments and start time.
            if pid in records() and identity(pid) == started:
                os.kill(pid, signal.SIGTERM)
                print(f"Sent SIGTERM to {pid}")
            else:
                print(f"Skipped changed process {pid}")


if __name__ == "__main__":
    main()
