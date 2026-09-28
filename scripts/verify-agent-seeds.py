#!/usr/bin/env python3
"""Execute the actual generated activation blocks in a disposable home."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

generation = Path(sys.argv[1])
repo = Path(sys.argv[2])
config_attr = sys.argv[3]
activation = (generation / "activate").read_text()
for name, relative in [("seedClaudeSettings", ".claude/settings.json"), ("seedCodexConfig", ".codex/config.toml"), ("seedCodexHooks", ".codex/hooks.json")]:
    attr = config_attr + ".config.home.activation." + name + ".data"
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
        if name == "seedClaudeSettings":
            target.unlink()
            target.symlink_to(Path(tmp) / "public-dotfiles/.claude/settings.json")
            run()
            assert not target.is_symlink() and target.read_text() == seed
        custom = Path(tmp) / "custom-settings"
        custom.write_text("operator owned")
        target.unlink()
        target.symlink_to(custom)
        run()
        assert target.is_symlink() and custom.read_text() == "operator owned"
print("mutable agent seeds: first install, writability, preservation, migration passed")

# Prove the actual pre-link activation retains existing private/runtime bytes.
block = subprocess.check_output([
    "nix", "--extra-experimental-features", "nix-command flakes", "eval", "--raw",
    config_attr + ".config.home.activation.detachMutableAgentConfigs.data",
], cwd=repo, text=True)
assert activation.index('"detachMutableAgentConfigs"') < activation.index('"linkGeneration"')
with tempfile.TemporaryDirectory(prefix="agent-detach-") as tmp:
    test_home = Path(tmp)
    source = test_home / "public-dotfiles/config/codex/hooks.json"
    source.parent.mkdir(parents=True)
    content = '{"hooks":{},"preserve_runtime_fixture":true}\n'
    source.write_text(content)
    live = test_home / ".codex/hooks.json"
    live.parent.mkdir()
    live.symlink_to(source)
    script = block.replace("/Users/example", tmp)
    subprocess.run(["bash", "-eu", "-c", script], env=dict(os.environ, DRY_RUN="1"), check=True, capture_output=True)
    assert live.is_symlink()
    subprocess.run(["bash", "-eu", "-c", script], env=dict(os.environ, DRY_RUN=""), check=True, capture_output=True)
    assert not live.is_symlink() and live.read_text() == content and source.read_text() == content
    assert live.stat().st_mode & 0o777 == 0o600
print("managed mutable links detached before linking without changing runtime bytes")
