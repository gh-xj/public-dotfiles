#!/usr/bin/env python3
"""Run actual generated activation blocks against isolated ownership fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("control", root / "scripts/public-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
activation = (Path(sys.argv[1]) / "activate").read_text()
bash = activation.splitlines()[0][2:]
blocks = dict(re.findall(r'_iNote "Activating %s" "([^"]+)"\n(.*?)(?=\n_iNote "Activating %s"|\Z)', activation, re.S))
order = list(blocks)
assert order.index("checkGhosttyParent") < order.index("checkLinkTargets") < order.index("writeBoundary")
assert order.index("writeBoundary") < order.index("detachMutableAgentConfigs") < order.index("linkGeneration")
assert "cleanOldGen" in blocks["linkGeneration"]

with tempfile.TemporaryDirectory(prefix="activation-guards-") as tmp:
    base = Path(tmp).resolve()
    home, repo, old = [base / name for name in ("home", "repo", "old")]
    source = repo / "config/codex/hooks.json"
    source.parent.mkdir(parents=True)
    source.write_text('{"private-fixture":true}\n')
    live = home / ".codex/hooks.json"
    live.parent.mkdir(parents=True)
    live.symlink_to(source)
    original = source.read_bytes()
    body = blocks["detachMutableAgentConfigs"].replace("/Users/example/public-dotfiles", str(repo)).replace("/Users/example", str(home))
    for dry in ("1", ""):
        env = dict(os.environ, DRY_RUN=dry)
        subprocess.run([bash, "-eu", "-c", body], check=True, env=env, capture_output=True)
        assert live.is_symlink() and live.read_bytes() == original
    env = dict(os.environ)
    env.pop("DRY_RUN", None)
    subprocess.run([bash, "-eu", "-c", body], check=True, env=env, capture_output=True)
    assert not live.is_symlink() and live.read_bytes() == original
    live.unlink()
    live.symlink_to(source)
    # Explicit downstream ownership is absolute, even for public-looking links.
    control.detach_mutable(home, repo, True, skip=[".codex/hooks.json"], legacy_only=control.MUTABLE)
    assert live.is_symlink()
    control.detach_mutable(home, repo, True, legacy_only=control.MUTABLE)
    assert not live.is_symlink() and live.read_bytes() == original
    # Disabled features do not take over unknown links.
    foreign = base / "foreign"
    foreign.write_text("foreign")
    live.unlink()
    live.symlink_to(foreign)
    control.detach_mutable(home, repo, True, legacy_only=control.MUTABLE)
    assert live.is_symlink()
    # Preserve old managed bytes even when the generation predates metadata.
    old_file = old / "home-files/.codex/hooks.json"
    old_file.parent.mkdir(parents=True)
    old_file.symlink_to(foreign)
    control.detach_mutable(home, repo, True, legacy_only=control.MUTABLE, old_generation=old)
    assert not live.is_symlink() and live.read_text() == "foreign"
    parent = home / ".config/ghostty"
    parent.parent.mkdir()
    parent.symlink_to(repo, target_is_directory=True)
    preflight = blocks["checkGhosttyParent"].replace("/Users/example", str(home))
    result = subprocess.run([bash, "-eu", "-c", preflight], capture_output=True)
    assert result.returncode != 0 and parent.is_symlink() and source.read_bytes() == original
    parent.unlink()
    parent.mkdir()
    subprocess.run([bash, "-eu", "-c", preflight], check=True)
print("activation guards: actual HM ordering, dry-run, feature disable, downstream ownership, Ghostty preflight passed")

with tempfile.TemporaryDirectory(prefix="settings-merge-") as tmp:
    home = Path(tmp).resolve()
    body = blocks["mergeClaudeSettings"].replace("/Users/example", str(home))
    declared = Path(re.search(r"^\s*declared=(\S+)$", body, re.M).group(1))
    wanted = json.loads(declared.read_text())
    live, base = home / ".claude/settings.json", home / ".local/state/public-dotfiles/settings-base/claude-settings.json"
    def activate(dry=False):
        env = dict(os.environ, DRY_RUN_CMD="echo" if dry else "")
        return subprocess.run([bash, "-eu", "-c", body], check=True, env=env, capture_output=True, text=True)
    activate(dry=True)
    assert not live.exists() and not base.exists()
    activate()
    assert json.loads(live.read_text()) == wanted and base.read_bytes() == declared.read_bytes()
    assert oct(live.stat().st_mode & 0o777) == "0o600"
    # Runtime keys and permission additions survive; declared keys follow the repo.
    runtime = dict(wanted, attribution={"commit": "runtime"}, runtimeOnly=True)
    runtime["permissions"] = dict(wanted["permissions"], allow=wanted["permissions"]["allow"] + ["Bash(runtime *)"])
    live.write_text(json.dumps(runtime))
    activate()
    merged = json.loads(live.read_text())
    assert merged["attribution"] == wanted["attribution"] and merged["runtimeOnly"] is True
    assert merged["permissions"]["allow"] == wanted["permissions"]["allow"] + ["Bash(runtime *)"]
    # Keys and entries dropped from the declaration since the last base disappear.
    base.write_text(json.dumps(dict(wanted, droppedKey=1, permissions=dict(wanted["permissions"], allow=wanted["permissions"]["allow"] + ["Bash(dropped *)"]))))
    live.write_text(json.dumps(dict(merged, droppedKey=1, permissions=dict(merged["permissions"], allow=merged["permissions"]["allow"] + ["Bash(dropped *)"]))))
    activate()
    merged = json.loads(live.read_text())
    assert "droppedKey" not in merged and "Bash(dropped *)" not in merged["permissions"]["allow"] and "Bash(runtime *)" in merged["permissions"]["allow"]
    live.write_text("{not json")
    result = activate()
    assert live.read_text() == "{not json" and "not mergeable JSON" in result.stderr
print("settings merge: creates, dry-runs, keeps runtime keys, follows declared and dropped keys, skips invalid JSON")

# A downstream activation may own the file without declaring any home.file.
expression = f'''let f = builtins.getFlake {json.dumps(str(root))};
  h = f.homeConfigurations.example.extendModules {{ modules = [{{
    xj.publicDotfiles.agents.codexHooks.seed.enable = false;
  }}]; }}; in h.config.home.activation.detachMutableAgentConfigs.data'''
opted_out = subprocess.run(control.NIX + ["eval", "--impure", "--raw", "--expr", expression],
                           check=True, capture_output=True, text=True).stdout
assert "--skip .codex/hooks.json" in opted_out
print("explicit seed opt-out remains authoritative without downstream home.file")
