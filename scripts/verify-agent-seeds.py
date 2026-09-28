#!/usr/bin/env python3
"""Execute the actual generated activation blocks in a disposable home."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

generation, repo = map(Path, sys.argv[1:])
activation = (generation / "activate").read_text()
for name, relative in [("seedClaudeSettings", ".claude/settings.json"), ("seedCodexConfig", ".codex/config.toml")]:
    attr = ".#homeConfigurations.example.config.home.activation." + name + ".data"
    block = subprocess.check_output(["nix", "--extra-experimental-features", "nix-command flakes", "eval", "--raw", attr], cwd=repo, text=True)
    assert name in activation and "/nix/store/" in block
    with tempfile.TemporaryDirectory(prefix="agent-seed-") as tmp:
        target = Path(tmp) / relative
        script = block.replace("/Users/example", tmp)
        env = dict(os.environ, DRY_RUN_CMD="")
        def run():
            subprocess.run(["bash", "-eu", "-c", script], env=env, check=True)
        run()
        assert target.is_file() and not target.is_symlink()
        assert target.stat().st_mode & 0o200
        seed = target.read_text()
        if name == "seedClaudeSettings":
            assert json.loads(seed)["teammateMode"] == "in-process"
        target.write_text(seed + "\n")
        run()
        assert target.read_text() == seed + "\n", "activation overwrote live edits"
        target.unlink()
        target.symlink_to("/nix/store/obsolete/config/" + relative)
        run()
        assert not target.is_symlink() and target.read_text() == seed
print("mutable agent seeds: first install, writability, preservation, migration passed")
