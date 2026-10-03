#!/usr/bin/env python3
"""Fixture tests for managed command provenance."""
import importlib.util
import os
from pathlib import Path
import tempfile

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("provenance", root / "scripts/provenance.py")
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)

with tempfile.TemporaryDirectory(prefix="provenance-") as tmp:
    base = Path(tmp)
    home, profile, brew = base / "home", base / "profile", base / "brew"
    for directory in (profile / "home-path/bin", home / ".local/share/mise/shims", brew / "bin"):
        directory.mkdir(parents=True)
    def executable(path):
        path.write_text("#!/bin/sh\n")
        path.chmod(0o755)
    executable(profile / "home-path/bin/task")
    for command in ("node", "npm", "npx", "corepack"):
        executable(home / ".local/share/mise/shims" / command)
    executable(brew / "bin/task")
    brewfile = base / "Brewfile"
    brewfile.write_text("")
    mise = base / "mise.toml"
    mise.write_text('[tools]\nnode = "1"\n')
    path = os.pathsep.join((str(profile / "home-path/bin"), str(home / ".local/share/mise/shims")))
    declared, issues = provenance.audit(home, profile, brewfile, mise, path)
    assert "task" in declared and "node" in declared and not issues
    duplicate = path + os.pathsep + str(brew / "bin")
    assert any(item.startswith("task ") and len(providers) == 2
               for item, providers in provenance.audit(home, profile, brewfile, mise, duplicate)[1])
    assert any(item.startswith("node ") and not providers
               for item, providers in provenance.audit(home, profile, brewfile, mise, str(profile / "home-path/bin"))[1])
print("managed command provenance fixtures passed")
