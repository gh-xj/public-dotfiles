#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="retention-") as tmp:
    root = Path(tmp)
    old = time.time() - 30 * 86400
    log = root / "job.log"
    log.write_text("".join(f"line {i}\n" for i in range(1000)))
    holder = open(log, "a")  # An O_APPEND writer must survive truncation.
    transcripts = root / "sessions"
    (transcripts / "2026").mkdir(parents=True)
    stale, fresh = transcripts / "2026/old.jsonl", transcripts / "2026/new.jsonl"
    stale.write_text("old\n"); fresh.write_text("new\n")
    os.utime(stale, (old, old))
    scratch = root / "scratch"
    (scratch / "stale-dir").mkdir(parents=True)
    (scratch / "stale-dir/file").write_text("x")
    (scratch / "fresh").write_text("y")
    for stale_path in (scratch / "stale-dir", scratch / "stale-dir/file"):
        os.utime(stale_path, (old, old))
    (scratch / "live-dir").mkdir()
    (scratch / "live-dir/active").write_text("z")  # A fresh file inside keeps an old directory alive.
    os.utime(scratch / "live-dir", (old, old))
    clones = root / "chrome-clones"
    for name in ("stale-free", "stale-open", "newest"):
        (clones / name / "Chrome.app/Contents/MacOS").mkdir(parents=True)
        (clones / name / "Chrome.app/Contents/MacOS/Chrome").write_text(name)
    os.utime(clones / "stale-free", (old - 100, old - 100))
    os.utime(clones / "stale-open", (old, old))
    fakebin = root / "bin"
    fakebin.mkdir()
    fake_lsof = fakebin / "lsof"
    fake_lsof.write_text("#!/bin/sh\nprintf 'p123\\ni%s\\n' \"$LIVE_INODE\"\n")
    fake_ps = fakebin / "ps"
    fake_ps.write_text("#!/bin/sh\nprintf '%s\\n' $RUNNING\n")
    for tool in (fake_lsof, fake_ps):
        tool.chmod(0o700)
    cache = root / "go-build"
    (cache / "0a").mkdir(parents=True)
    (cache / "0a/entry-d").write_bytes(b"x" * 8192)
    (cache / "README").write_text("cache")
    config = root / "config.json"
    config.write_text(json.dumps({
        "logs": {"globs": [str(root / "*.log")], "maxBytes": 2000}, "archiveDirectory": str(root / "archive"),
        "archives": [{"name": "agent", "root": str(transcripts), "glob": "**/*.jsonl", "keepDays": 14}],
        "scratch": [{"root": str(scratch), "maxAgeDays": 14}],
        "chromeCodeSignClones": {"enable": True, "maxAgeDays": 1, "root": str(clones)},
        "caches": [{"name": "goBuild", "root": str(cache), "maxGiB": 1, "busyProcesses": ["compile"]}]}))
    live = (clones / "stale-open/Chrome.app/Contents/MacOS/Chrome").stat().st_ino
    environment = dict(os.environ, RETENTION_LSOF=str(fake_lsof), RETENTION_PS=str(fake_ps), LIVE_INODE=str(live), RUNNING="/sbin/launchd")
    run = lambda *flags, **extra: json.loads(subprocess.run([sys.executable, str(repo / "scripts/retention.py"), str(config), *flags],
                                                    check=True, capture_output=True, text=True, env=dict(environment, **extra)).stdout)
    assert run()["caches"][0]["action"] == "under-cap"
    config.write_text(config.read_text().replace('"maxGiB": 1', '"maxGiB": 0'))  # Every non-empty cache is over a zero cap.
    assert run(RUNNING="/usr/local/go/pkg/tool/darwin_arm64/compile")["caches"][0]["action"] == "busy"
    assert (cache / "0a/entry-d").exists(), "a running writer defers clearing"
    plan = run()
    assert plan["caches"][0]["action"] == "over-cap" and (cache / "README").exists() and "free_delta_bytes" not in plan
    assert plan["mode"] == "dry-run" and len(plan["logs"]) == len(plan["archives"]) == len(plan["scratch"]) == len(plan["chrome_clones"]) == 1
    assert log.stat().st_size > 2000 and stale.exists() and (scratch / "stale-dir").exists(), "dry-run must change nothing"
    assert (clones / "stale-free").exists(), "dry-run must preserve Chrome clones"
    jobs = Path(tmp) / "jobs"
    assert run("--apply", "--status-directory", str(jobs))["mode"] == "apply"
    outcome = json.loads((jobs / "workstation-retention.json").read_text())
    assert outcome["ok"] and outcome["expires"] > outcome["at"]
    assert cache.is_dir() and not any(cache.iterdir()), "an over-cap cache is emptied, its root kept"
    assert 800 < log.stat().st_size <= 1000 and log.read_text().startswith("line "), "log keeps whole recent lines"
    holder.write("after\n"); holder.flush()
    assert log.read_text().endswith("after\n") and "\0" not in log.read_text()
    assert not stale.exists() and fresh.exists()
    archived = list((root / "archive").glob("agent-*.tar.zst"))
    assert len(archived) == 1 and subprocess.run(["tar", "--zstd", "-tf", str(archived[0])], capture_output=True, text=True).stdout.split() == ["2026/old.jsonl"]
    assert not (scratch / "stale-dir").exists() and (scratch / "fresh").exists() and (scratch / "live-dir/active").exists()
    assert not (clones / "stale-free").exists() and (clones / "stale-open").exists() and (clones / "newest").exists()
    again = run("--apply")
    assert isinstance(again.pop("free_delta_bytes"), int)
    assert again == {"mode": "apply", "logs": [], "archives": [], "scratch": [], "chrome_clones": [],
                     "caches": [{"cache": "goBuild", "allocated_gib": 0.0, "cap_gib": 0, "action": "under-cap"}]}, "second run is a no-op"
print("retention dry-run, log cap, verified archive, scratch expiry, Chrome liveness and cache cap fixtures passed")
