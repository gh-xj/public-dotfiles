#!/usr/bin/env python3
"""Verify live Ghostty ownership and effective settings against its HM generation."""
import argparse
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile


def settings(text):
    selected = {key: [] for key in ("font-family", "theme", "command", "keybind")}
    for line in text.splitlines():
        key, sep, value = line.partition(" = ")
        if sep and key in selected:
            selected[key].append(value)
    # Ghostty emits normalized keybindings; their serialization order can vary.
    selected["keybind"].sort()
    return selected


def verify(home, generation, ghostty, alternate_home=False):
    parent = home / ".config/ghostty"
    try:
        mode = parent.lstat().st_mode
    except FileNotFoundError:
        raise ValueError("Ghostty directory is missing; run the owning Home Manager apply")
    if not stat.S_ISDIR(mode):
        raise ValueError("Ghostty parent must be a real directory; run the legacy-parent migration before apply")
    leaf = parent / "config"
    if not leaf.is_file():
        raise ValueError("Ghostty config leaf is missing or dangling; rerun the owning Home Manager apply")
    expected = (generation / "home-files/.config/ghostty/config").resolve(strict=True)
    if not str(expected).startswith("/nix/store/") or leaf.resolve(strict=True) != expected:
        raise ValueError("Ghostty config does not resolve to the supplied/current Home Manager generation")
    env = dict(os.environ)
    if alternate_home:
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
    def run(*args, environment=None):
        result = subprocess.run([ghostty, *args], env=environment or env, capture_output=True, text=True)
        if result.returncode:
            raise ValueError(f"Ghostty {args[0]} failed (exit {result.returncode}): {result.stderr.strip()}")
        return result.stdout
    run("+validate-config")
    actual_settings = settings(run("+show-config"))
    # show-config on released Ghostty versions accepts only action-specific
    # flags. Use an isolated HOME/XDG config to normalize the generated file
    # without inheriting macOS Application Support overrides from the live home.
    # Foundation's directory lookup needs CFFIXED_USER_HOME as well as HOME;
    # fixtures prove both XDG and Application Support overrides are detected.
    with tempfile.TemporaryDirectory(prefix="ghostty-expected-") as tmp:
        expected_env = dict(os.environ, HOME=tmp, CFFIXED_USER_HOME=tmp, XDG_CONFIG_HOME=str(generation / "home-files/.config"))
        expected_settings = settings(run("+show-config", environment=expected_env))
    for key, desired in expected_settings.items():
        if not desired:
            raise ValueError(f"generated Ghostty config does not declare expected {key}")
        if actual_settings[key] != desired:
            raise ValueError(f"effective Ghostty {key} differs from the generation; inspect other Ghostty config locations/overrides")
    print("live Ghostty: real parent, current generation, validation, font, theme, command and keybindings verified")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", required=True)
    parser.add_argument("--home", type=Path, help="alternate home (also isolates Ghostty's config lookup)")
    parser.add_argument("--generation", type=Path, help="defaults to the live home-manager profile")
    parser.add_argument("--ghostty", help="Ghostty executable override")
    args = parser.parse_args()
    home = args.home or Path.home()
    generation = args.generation or home / ".local/state/nix/profiles/home-manager"
    ghostty = args.ghostty or shutil.which("ghostty") or "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    try:
        verify(home, generation.resolve(strict=True), ghostty, alternate_home=args.home is not None)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Ghostty verification: {error}\n")


if __name__ == "__main__":
    main()
