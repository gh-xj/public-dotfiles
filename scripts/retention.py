#!/usr/bin/env python3
"""Bound state that only grows: cap logs, archive old agent transcripts, expire scratch, cap build caches.

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


def allocated_size(path):
    """Allocated bytes with hardlinked inodes counted once; APFS clone savings still need a df delta."""
    total, seen = 0, set()
    candidates = [path]
    if path.is_dir() and not path.is_symlink():
        candidates.extend(Path(directory) / name for directory, names, files in os.walk(path) for name in names + files)
    for candidate in candidates:
        try:
            stat = candidate.lstat()
        except FileNotFoundError:  # A concurrent writer trimmed it; the busy guard runs after sizing.
            continue
        identity = (stat.st_dev, stat.st_ino)
        if identity not in seen:
            seen.add(identity)
            total += stat.st_blocks * 512
    return total


def chrome_clone_root(spec):
    if spec.get("root"):
        return Path(os.path.expanduser(spec["root"]))
    temporary = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], check=True, capture_output=True, text=True).stdout.strip()
    return Path(temporary).parent / "X" / "com.google.Chrome.code_sign_clone"


def live_inodes():
    """Executable inodes mapped by running Chrome processes; a clone hard-links the binary it was made for."""
    lsof = os.environ.get("RETENTION_LSOF", "lsof")
    result = subprocess.run([lsof, "-n", "-a", "-d", "txt", "-c", "Google Chrome", "-Fpi"], capture_output=True, text=True)
    # lsof exits 1 for both "no match" and a real error; only the error writes to stderr.
    if result.returncode not in (0, 1) or (result.returncode == 1 and result.stderr.strip()):
        return None
    return {int(line[1:]) for line in result.stdout.splitlines() if line.startswith("i") and line[1:].isdigit()}


def expire_chrome_clones(spec, apply, now):
    """Remove only old clones whose executable no running Chrome maps, and always preserve the newest clone."""
    if not spec.get("enable", False):
        return []
    root = chrome_clone_root(spec)
    if not root.is_dir() or root.is_symlink():
        return []
    clones = [entry for entry in root.iterdir() if entry.is_dir() and not entry.is_symlink()]
    if len(clones) < 2:
        return []
    newest = max(clones, key=lambda entry: entry.stat().st_mtime)
    running = live_inodes()
    if running is None:
        return [{"chrome_clone": str(root), "action": "skipped", "note": "lsof txt query failed; nothing removed"}]
    cutoff = now - spec["maxAgeDays"] * 86400
    done = []
    for clone in sorted(clones):
        if clone == newest or clone.stat().st_mtime >= cutoff:
            continue
        if any(binary.stat().st_ino in running for binary in clone.glob("*/Contents/MacOS/*")):
            continue
        done.append({"chrome_clone": str(clone), "allocated_bytes": allocated_size(clone),
                     "note": "APFS clones share blocks; only the post-delete df delta is authoritative"})
        if apply:
            shutil.rmtree(clone)
    return done


def running_commands():
    ps = os.environ.get("RETENTION_PS", "ps")
    lines = subprocess.run([ps, "-axo", "comm="], check=True, capture_output=True, text=True).stdout.splitlines()
    return {os.path.basename(line.strip()) for line in lines if line.strip()}


def cap_caches(specs, apply):
    """Empty a regenerable cache above its cap unless one of its writers runs; the root itself stays."""
    done, running = [], running_commands() if specs else set()
    for spec in specs:
        root = Path(os.path.expanduser(spec["root"]))
        if not root.is_dir() or root.is_symlink():
            continue
        size = allocated_size(root)
        item = {"cache": spec["name"], "allocated_gib": round(size / 2**30, 2), "cap_gib": spec["maxGiB"], "action": "under-cap"}
        done.append(item)
        if size <= spec["maxGiB"] * 2**30 or not any(root.iterdir()):
            continue
        item["action"] = "busy" if running & set(spec["busyProcesses"]) else "over-cap"
        if apply and item["action"] == "over-cap":
            failed = 0
            for entry in root.iterdir():
                try:
                    shutil.rmtree(entry) if entry.is_dir() and not entry.is_symlink() else entry.unlink()
                except OSError:  # A concurrent build recreated or holds entries.
                    failed += 1
            item["action"] = "partial" if failed else "cleared"
    return done


def free_bytes(path):
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize


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
    free_before = free_bytes(Path.home())
    report = {"mode": "apply" if args.apply else "dry-run",
              "logs": cap_logs(config["logs"], args.apply),
              "archives": [item for spec in config["archives"] for item in archive(spec, Path(os.path.expanduser(config["archiveDirectory"])), args.apply, now)],
              "scratch": [item for spec in config["scratch"] for item in expire_scratch(spec, args.apply, now)],
              "chrome_clones": expire_chrome_clones(config.get("chromeCodeSignClones", {}), args.apply, now),
              "caches": cap_caches(config.get("caches", []), args.apply)}
    if args.apply:  # The cleanup protocol accepts reclaim by free-space delta, not by summed sizes.
        report["free_delta_bytes"] = free_bytes(Path.home()) - free_before
    if args.apply and args.status_directory:
        record_job(args.status_directory, "workstation-retention", True, 2 * 86400, now,
                   f'{len(report["logs"])} logs, {len(report["archives"])} archives, '
                   f'{len(report["scratch"])} scratch, {len(report["chrome_clones"])} Chrome clones, '
                   f'{sum(item["action"] in ("cleared", "partial") for item in report["caches"])} caches cleared')
    print(json.dumps(report))


if __name__ == "__main__":
    sys.exit(main())
