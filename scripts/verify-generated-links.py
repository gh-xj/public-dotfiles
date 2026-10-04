#!/usr/bin/env python3
"""Verify generated links, mutable exclusions, and native config parsers."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

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
    # Out-of-store targets are repo-owned trees; only the declared link must resolve.
    if target.is_dir() and target.is_relative_to("/nix/store"):
        assert target not in ancestors, f"directory cycle: {path}"
        for child in target.iterdir():
            visit(child, (*ancestors, target))


visit(generated)

tmux_config = resolve(generated / ".config/tmux/tmux.conf").read_text()
provider_line = next(line for line in tmux_config.splitlines() if line.startswith("set-environment -g PATH "))
server_paths = shlex.split(provider_line)[3].split(":")
assert str((generation / "home-path").resolve() / "bin") in server_paths, "tmux must use its generation's tools"
assert all(path.startswith("/nix/store/") for path in server_paths[:3]), "pin Bash/tmux/profile before fallbacks"
if "\nrun-shell" in tmux_config:
    assert tmux_config.index(provider_line) < tmux_config.index("\nrun-shell"), "set server providers before plugins"

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
    subprocess.run(["nix", "--extra-experimental-features", "nix-command flakes", "eval", "--json", "--impure", "--expr", expression],
                   check=True, stdout=subprocess.DEVNULL)
    parsed += len(toml_files)

with tempfile.TemporaryDirectory(prefix="generated-shell-") as directory:
    fixture = Path(directory)
    (fixture / ".zshenv").write_text(resolve(generated / ".zshenv").read_text())
    profile_text = resolve(generated / ".zprofile").read_text()
    (fixture / ".zprofile").write_text(profile_text.replace("/bin/launchctl setenv", "/usr/bin/true"))
    (fixture / ".zshrc").write_text("source " + shlex.quote(str(resolve(generated / ".zshrc"))) + "\n")
    private = fixture / ".config/zsh/private.zshenv"
    private.parent.mkdir(parents=True)
    private.write_text('export PATH="$HOME/fixture-private:$PATH"\n'
                       'print -r -- loaded >> "$HOME/private-loads"\n')
    env = {"HOME": str(fixture), "ZDOTDIR": str(fixture), "PATH": "/usr/bin:/bin",
           "PUBLIC_DOTFILES_STARTUP_PATH": "inherited-value-must-not-leak", "ZSH_MINIMAL": "1"}
    observed = []
    for flags in ("-c", "-lc", "-ic", "-lic"):
        result = subprocess.run(["/bin/zsh", flags, 'print -r -- "$PATH"; /usr/bin/env'],
                                env=env, check=True, capture_output=True, text=True)
        lines = result.stdout.splitlines()
        observed.append(lines[0])
        assert not any(line.startswith("PUBLIC_DOTFILES_STARTUP_PATH=") for line in lines[1:])
    assert len(set(observed)) == 1, "shell startup changed the declared provider order"
    assert (fixture / "private-loads").read_text().splitlines() == ["loaded"] * 4, "private environment must load once per shell"
    nested = subprocess.run(["/bin/zsh", "-lc", "/bin/zsh -lc 'print -r -- \"$PATH\"'"],
                            env=env, check=True, capture_output=True, text=True)
    assert nested.stdout.strip() == observed[0], "nested login shell changed provider order"
print(f"generated state: links resolve, mutable targets excluded, shell provider order verified, {parsed} configs parsed")
