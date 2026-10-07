#!/usr/bin/env python3
"""Fixture tests for managed command provenance."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.dont_write_bytecode = True
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
    declared, issues = provenance.audit(home, profile, [brewfile], mise, path)
    assert "task" in declared and "node" in declared and not issues
    duplicate = path + os.pathsep + str(brew / "bin")
    assert any(item.startswith("task ") and len(providers) == 2
               for item, providers in provenance.audit(home, profile, [brewfile], mise, duplicate)[1])
    assert any(item.startswith("node ") and not providers
               for item, providers in provenance.audit(home, profile, [brewfile], mise, str(profile / "home-path/bin"))[1])
    for command in ("node", "npm", "npx", "corepack"):
        executable(brew / "bin" / command)
    original_label = provenance.label
    def fixture_label(directory, fixture_home, fixture_profile):
        return "homebrew" if directory == brew / "bin" else original_label(directory, fixture_home, fixture_profile)
    with patch.object(provenance, "label", side_effect=fixture_label):
        wrong_path = os.pathsep.join((str(profile / "home-path/bin"), str(brew / "bin")))
        mismatches = provenance.audit(home, profile, [brewfile], mise, wrong_path)[1]
        assert all((command + " [mise]", ["homebrew"]) in mismatches for command in ("node", "npm", "npx", "corepack"))
    local = home / ".local/bin"
    local.mkdir(parents=True)
    executable(local / "task")
    assert ("task [nix]", ["user-local"]) in provenance.audit(home, profile, [brewfile], mise, str(local))[1]
    overlay = base / "Brewfile.overlay"
    overlay.write_text('brew "mosh"\n')
    brewfile.write_text('brew "duti"\n')
    assert provenance.brew_commands([brewfile, overlay], None)[0] == {"duti", "mosh"}
print("managed command provenance fixtures passed")
