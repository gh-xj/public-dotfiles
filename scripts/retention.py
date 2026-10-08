#!/usr/bin/env python3
"""Bound state that only grows: cap logs, archive old agent transcripts, expire scratch.

Dry-run unless --apply. The JSON config comes from the Home Manager module.
"""
import argparse
import glob
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def cap_logs(spec, apply):
    """Truncate in place to the newest half of the cap, so O_APPEND writers and `tail -F` keep working."""
    done = []
    for pattern in spec["globs"]:
        for name in glob.glob(os.path.expanduser(pattern)):
            path = Path(name)
            if path.is_symlink() or not path.is_file() or path.stat().st_size <= spec["maxBytes"]:
                continue
            done.append({"log": name, "bytes": path.stat().st_size, "frees": path.stat().st_size - spec["maxBytes"] // 2})
            if apply:
                with open(path, "r+b") as log:
                    log.seek(-spec["maxBytes"] // 2, os.SEEK_END)
                    log.readline()  # Start on a line boundary.
                    tail = log.read()
                    log.seek(0)
                    log.write(tail)
                    log.truncate()
    return done


def archive(spec, destination, apply, now):
    """One tar.zst per mtime day; originals are removed only after the archive lists back identically."""
    root = Path(os.path.expanduser(spec["root"]))
    cutoff = now - spec["keepDays"] * 86400
    days = {}
    for path in root.glob(spec["glob"]):
        if path.is_file() and not path.is_symlink() and path.stat().st_mtime < cutoff:
            days.setdefault(time.strftime("%Y-%m-%d", time.localtime(path.stat().st_mtime)), []).append(path.relative_to(root).as_posix())
    done = []
    for day, names in sorted(days.items()):
        target = destination / f'{spec["name"]}-{day}.tar.zst'
        if target.exists():
            target = target.with_name(f'{spec["name"]}-{day}-{int(now)}.tar.zst')
        done.append({"archive": str(target), "files": len(names), "source_bytes": sum((root / n).stat().st_size for n in names)})
        if not apply:
            continue
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        part = target.with_suffix(".part")
        subprocess.run(["tar", "--zstd", "-cf", str(part), "-C", str(root), "--", *names], check=True)
        listed = subprocess.run(["tar", "--zstd", "-tf", str(part)], check=True, capture_output=True, text=True).stdout.split("\n")
        if sorted(filter(None, listed)) != sorted(names):
            part.unlink()
            raise SystemExit(f"archive verification failed for {target.name}; originals kept")
        os.replace(part, target)
        for name in names:
            (root / name).unlink()
    return done


def expire_scratch(spec, apply, now):
    root = Path(os.path.expanduser(spec["root"].replace("{uid}", str(os.getuid()))))
    done = []
    if root.is_dir() and not root.is_symlink():
        for entry in root.iterdir():
            newest = max([entry.lstat().st_mtime] + [os.lstat(os.path.join(d, n)).st_mtime for d, _, names in os.walk(entry) for n in names])
            if now - newest > spec["maxAgeDays"] * 86400:  # Anything touched inside keeps the entry alive.
                done.append({"scratch": str(entry), "bytes": sum(os.lstat(os.path.join(d, n)).st_size for d, _, names in os.walk(entry) for n in names)})
                if apply:
                    shutil.rmtree(entry) if entry.is_dir() and not entry.is_symlink() else entry.unlink()
    return done


def record_job(directory, name, ok, ttl, now, detail):
    """Outcome file read by `task doctor`; `expires` is when silence becomes a finding."""
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    part = directory / (name + ".json.part")
    part.write_text(json.dumps({"ok": ok, "at": int(now), "expires": int(now + ttl), "detail": detail}))
    os.replace(part, directory / (name + ".json"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--status-directory", type=Path, help="record the outcome for `task doctor`")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    now = time.time()
    report = {"mode": "apply" if args.apply else "dry-run",
              "logs": cap_logs(config["logs"], args.apply),
              "archives": [item for spec in config["archives"] for item in archive(spec, Path(os.path.expanduser(config["archiveDirectory"])), args.apply, now)],
              "scratch": [item for spec in config["scratch"] for item in expire_scratch(spec, args.apply, now)]}
    if args.apply and args.status_directory:
        record_job(args.status_directory, "workstation-retention", True, 2 * 86400, now,
                   f'{len(report["logs"])} logs, {len(report["archives"])} archives, {len(report["scratch"])} scratch')
    print(json.dumps(report))


if __name__ == "__main__":
    sys.exit(main())
