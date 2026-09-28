#!/usr/bin/env python3
"""Manifest-owned scratch directories; expired entries move to recoverable quarantine."""
import argparse
import json
import os
from pathlib import Path
import re
import time
import uuid


def sizes(path):
    logical = allocated = 0
    seen = set()
    for directory, _, files in os.walk(path, followlinks=False):
        for name in files:
            item = Path(directory) / name
            stat = item.lstat()
            key = (stat.st_dev, stat.st_ino)
            if key not in seen:
                seen.add(key)
                logical += stat.st_size
                allocated += stat.st_blocks * 512
    return {"logical_bytes": logical, "allocated_bytes_estimate": allocated}


def manifest(path):
    file = path / "manifest.json"
    if path.is_symlink() or not path.is_dir() or file.is_symlink():
        return None
    try:
        value = json.loads(file.read_text())
        if value.get("version") != 1 or value.get("id") != path.name:
            return None
        if not isinstance(value["purpose"], str) or not isinstance(value["expires_at"], (int, float)):
            return None
        if not (0 < value["expires_at"] - value["created_at"] <= 720 * 3600):
            return None
        return value
    except (OSError, ValueError, KeyError, TypeError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(os.getenv("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "agent-scratch")
    sub = parser.add_subparsers(dest="action", required=True)
    new = sub.add_parser("new")
    new.add_argument("namespace")
    new.add_argument("--purpose", required=True)
    new.add_argument("--ttl-hours", type=float, default=24)
    sub.add_parser("ls")
    collect = sub.add_parser("collect")
    collect.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.root.is_symlink():
        parser.error("scratch root must not be a symlink")
    root = args.root.absolute()
    if root in (Path("/"), Path.home(), Path.cwd()):
        parser.error("use a dedicated scratch root")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.action == "new":
        if not re.fullmatch(r"[a-z][a-z0-9-]{0,31}", args.namespace) or not 0 < args.ttl_hours <= 720:
            parser.error("namespace: lowercase letters/digits/hyphens; TTL: >0 and <=720 hours")
        now = time.time()
        name = args.namespace + "-" + uuid.uuid4().hex
        path = root / name
        path.mkdir(mode=0o700)
        (path / "manifest.json").write_text(json.dumps({"version": 1, "id": name, "purpose": args.purpose,
                                                       "created_at": now, "expires_at": now + args.ttl_hours * 3600}))
        print(path)
        return
    for path in sorted(root.iterdir()):
        if path.name.startswith("."):
            continue
        value = manifest(path)
        if value is None:
            print(json.dumps({"path": str(path), "action": "skip-unmanaged"}))
            continue
        expired = value["expires_at"] <= time.time()
        report = {"path": str(path), "expired": expired, **sizes(path)}
        if args.action == "collect" and expired:
            report["action"] = "would-quarantine"
            if args.apply:
                quarantine = root / ".quarantine"
                if quarantine.is_symlink():
                    raise SystemExit("quarantine must not be a symlink")
                quarantine.mkdir(mode=0o700, exist_ok=True)
                # Recheck ownership after sizing. Rename stays on the same filesystem.
                if manifest(path) != value:
                    raise SystemExit("manifest changed during collection")
                destination = quarantine / (path.name + "-" + uuid.uuid4().hex[:8])
                path.rename(destination)
                report.update(action="quarantined", recover_from=str(destination))
        print(json.dumps(report))


if __name__ == "__main__":
    main()
