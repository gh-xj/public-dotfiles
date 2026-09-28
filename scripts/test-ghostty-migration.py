#!/usr/bin/env python3
"""Exercise the migration and HM's real leaf linker in disposable home/repo fixtures."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parent.parent
generation = Path(sys.argv[1]).resolve()
config_attr = sys.argv[2]
activation = (generation / "activate").read_text()
assert activation.index('"migrateGhosttyParent"') < activation.index('"checkLinkTargets"')
assert activation.index('"migrateGhosttyParent"') < activation.index('"linkGeneration"')
linker = re.search(r'-exec bash (/nix/store/\S+-link) ', activation).group(1)
home_files = (generation / "home-files").resolve()
generated_leaf = home_files / ".config/ghostty/config"
assert str(generated_leaf.resolve(strict=True)).startswith("/nix/store/")
nix = ["nix", "--extra-experimental-features", "nix-command flakes", "eval", "--raw"]
block = subprocess.check_output([*nix, config_attr + ".config.home.activation.migrateGhosttyParent.data"], cwd=repo, text=True)


with tempfile.TemporaryDirectory(prefix="ghostty-migration-") as tmp:
    base = Path(tmp)
    fixture_repo = base / "checkout with spaces"
    legacy = fixture_repo / ".config/ghostty"
    legacy.mkdir(parents=True)
    (legacy / "keep.txt").write_text("original target data")
    original_repo_files = sorted(p.relative_to(fixture_repo) for p in fixture_repo.rglob("*"))
    def setup(name):
        home = base / name
        (home / ".config").mkdir(parents=True)
        return home, home / ".config/ghostty"
    def migrate(home, apply=True, success=True):
        result = subprocess.run(["zsh", str(repo / "scripts/migrate-ghostty-parent.zsh"), "--home", str(home),
                                 "--repo", str(fixture_repo), "--apply" if apply else "--dry-run"], capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stderr
        return result.stdout + result.stderr
    def link(home):
        # Execute HM's generated link helper, restricted to the Ghostty leaf.
        env = dict(os.environ, HOME=str(home), PATH=str(generation / "home-path/bin") + ":" + os.environ["PATH"])
        for key in ("DRY_RUN", "DRY_RUN_CMD", "HOME_MANAGER_BACKUP_EXT", "HOME_MANAGER_BACKUP_COMMAND"):
            env.pop(key, None)
        subprocess.run(["bash", linker, str(home_files), str(generated_leaf)], env=env, check=True, capture_output=True)
        assert not (home / ".config/ghostty").is_symlink()
        assert (home / ".config/ghostty/config").resolve(strict=True) == generated_leaf.resolve(strict=True)
        assert sorted(p.relative_to(fixture_repo) for p in fixture_repo.rglob("*")) == original_repo_files
        assert (legacy / "keep.txt").read_text() == "original target data"

    home, parent = setup("known")
    parent.symlink_to(legacy, target_is_directory=True)
    assert "unlink legacy parent" in migrate(home, apply=False)
    assert parent.is_symlink() and not (legacy / "config").exists()
    migrate(home)
    assert parent.is_dir() and not parent.is_symlink()
    link(home)
    before = parent.stat().st_ino
    migrate(home)
    assert parent.stat().st_ino == before
    link(home)
    verifier = [sys.executable, str(repo / "scripts/verify-ghostty.py"), "--live", "--home", str(home), "--generation", str(generation)]
    good = subprocess.run(verifier, capture_output=True, text=True)
    assert good.returncode == 0, good.stderr
    # A valid leaf alone is insufficient: later config files can silently restore
    # the default shell. Verify the effective command, not just text in the leaf.
    override = home / ".config/ghostty/config.ghostty"
    override.write_text("command = /bin/zsh\n")
    bad = subprocess.run(verifier, capture_output=True, text=True)
    assert bad.returncode != 0 and "effective Ghostty command" in bad.stderr, bad.stderr
    override.write_text("font-size = invalid\n")
    bad = subprocess.run(verifier, capture_output=True, text=True)
    assert bad.returncode != 0 and "+validate-config failed" in bad.stderr, bad.stderr
    override.unlink()
    override = home / "Library/Application Support/com.mitchellh.ghostty/config"
    override.parent.mkdir(parents=True)
    override.write_text("command = /bin/zsh\n")
    bad = subprocess.run(verifier, capture_output=True, text=True)
    assert bad.returncode != 0 and "effective Ghostty command" in bad.stderr, bad.stderr
    override.unlink()
    (parent / "config").unlink()
    (parent / "config").symlink_to(generation / "activate")
    bad = subprocess.run(verifier, capture_output=True, text=True)
    assert bad.returncode != 0 and "current Home Manager generation" in bad.stderr
    link(home)

    home, parent = setup("relative")
    parent.symlink_to(os.path.relpath(legacy, parent.parent), target_is_directory=True)
    migrate(home)
    link(home)

    home, parent = setup("unknown")
    outside = base / "unrelated"
    outside.mkdir()
    parent.symlink_to(outside, target_is_directory=True)
    for apply in (False, True):
        assert "refusing unknown" in migrate(home, apply=apply, success=False)
        assert parent.is_symlink() and not list(outside.iterdir())

    home, parent = setup("unknown-dangling")
    parent.symlink_to(base / "absent")
    migrate(home, success=False)
    assert parent.is_symlink()

    home, parent = setup("normal")
    parent.mkdir()
    link(home)
    leaf_inode = (parent / "config").lstat().st_ino
    assert migrate(home) == ""
    assert (parent / "config").lstat().st_ino == leaf_inode

    home, parent = setup("missing")
    migrate(home, apply=False)
    assert not parent.exists()
    migrate(home)
    link(home)

    home, parent = setup("file")
    parent.write_text("preserve")
    migrate(home, success=False)
    assert parent.read_text() == "preserve"

    home = base / "unsafe-ancestor"
    home.mkdir()
    (home / ".config").symlink_to(fixture_repo / ".config", target_is_directory=True)
    migrate(home, success=False)
    assert not (legacy / "config").exists()

    # Actual activation block: ensure HM dry-run propagates and unknown links fail.
    home, parent = setup("activation")
    parent.symlink_to(legacy, target_is_directory=True)
    script = block.replace("/Users/example/public-dotfiles", shlex.quote(str(fixture_repo))).replace("/Users/example", shlex.quote(str(home)))
    subprocess.run(["bash", "-eu", "-c", script], env=dict(os.environ, DRY_RUN="1"), check=True, capture_output=True)
    assert parent.is_symlink()
    subprocess.run(["bash", "-eu", "-c", script], env=dict(os.environ, DRY_RUN=""), check=True, capture_output=True)
    link(home)

    # A removed legacy checkout directory leaves a dangling known parent link.
    home, parent = setup("known-dangling")
    alternate_repo = base / "empty-checkout"
    (alternate_repo / ".config").mkdir(parents=True)
    parent.symlink_to(alternate_repo / ".config/ghostty", target_is_directory=True)
    result = subprocess.run(["zsh", str(repo / "scripts/migrate-ghostty-parent.zsh"), "--home", str(home),
                             "--repo", str(alternate_repo), "--apply"], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert parent.is_dir() and not parent.is_symlink()
    assert not (alternate_repo / ".config/ghostty").exists()

    # The stock bootstrap preflight must call this engine without changing home.
    home, parent = setup("bootstrap-dry-run")
    parent.symlink_to(repo / ".config/ghostty", target_is_directory=True)
    env = dict(os.environ, HOME=str(home), USER="fixture", XJ_PUBLIC_DOTFILES_BOOTSTRAP_DIR=str(base / "bootstrap-state"))
    dry = subprocess.run(["bash", str(repo / "scripts/bootstrap-macos.sh"), "--dry-run", "--skip-build"], env=env, text=True, capture_output=True)
    assert dry.returncode == 0, dry.stderr
    assert "unlink legacy parent" in dry.stdout and parent.is_symlink()

print("Ghostty migration: known/unknown/relative/dangling links, real/missing directory, dry-run, idempotence, actual HM linker and clean checkout passed")
