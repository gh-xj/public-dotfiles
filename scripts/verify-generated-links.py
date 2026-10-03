#!/usr/bin/env python3
"""Verify generated links, mutable exclusions, and native config parsers."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("generation", type=Path)
parser.add_argument("--map", action="append", default=[], metavar="DECLARED=CHECKOUT")
args = parser.parse_args()
generation = args.generation.resolve()
generated = (generation / "home-files").resolve()
mappings = []
for item in args.map:
    declared, separator, checkout = item.partition("=")
    if not separator or not declared.startswith("/") or not checkout:
        parser.error("--map requires DECLARED=CHECKOUT absolute paths")
    mappings.append((Path(declared), Path(checkout).resolve()))


def resolve(path, seen=()):
    if path in seen:
        raise AssertionError(f"link cycle: {path}")
    for declared, checkout in mappings:
        if path.is_relative_to(declared):
            path = checkout / path.relative_to(declared)
            break
    if path.is_symlink():
        dest = Path(os.readlink(path))
        return resolve(dest if dest.is_absolute() else path.parent / dest, (*seen, path))
    assert path.exists(), f"dangling generated target: {path}"
    return path


def visit(path, ancestors=()):
    target = resolve(path)
    if target.is_dir():
        assert target not in ancestors, f"directory cycle: {path}"
        for child in target.iterdir():
            visit(child, (*ancestors, target))


visit(generated)

for relative in (".claude/settings.json", ".codex/config.toml", ".codex/hooks.json"):
    assert not (generated / relative).exists(), f"mutable target is owned by home.file: {relative}"

parsed = 0
toml_files = []
for path in generated.rglob("*"):
    if not path.is_file():
        continue
    resolved = resolve(path)
    suffix = resolved.suffix.lower()
    if suffix == ".json":
        json.loads(resolved.read_text())
        parsed += 1
    elif suffix in (".yaml", ".yml"):
        subprocess.run(["ruby", "-ryaml", "-e", "YAML.safe_load(File.read(ARGV[0]), aliases: true)", str(resolved)],
                       check=True)
        parsed += 1
    elif suffix == ".toml":
        toml_files.append(resolved)
    elif resolved.name in (".zshenv", ".zprofile", ".zshrc") or suffix == ".zsh":
        subprocess.run([str(generation / "home-path/bin/zsh"), "-n", str(resolved)], check=True)
        parsed += 1

if toml_files:
    expression = "map (path: builtins.fromTOML (builtins.readFile path)) [ " + " ".join(
        json.dumps(str(path)) for path in toml_files) + " ]"
    subprocess.run(["nix", "--extra-experimental-features", "nix-command flakes", "eval", "--impure", "--expr", expression],
                   check=True, stdout=subprocess.DEVNULL)
    parsed += len(toml_files)

print(f"generated state: links resolve, mutable targets excluded, {parsed} configs parsed")
