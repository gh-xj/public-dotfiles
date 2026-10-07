#!/usr/bin/env python3
"""Verify generated links, mutable exclusions, and native config parsers."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
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
    if path in seen: raise AssertionError(f"link cycle: {path}")
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
def owned_files(target):
    # Live links point into checkouts that also hold ignored runtime state
    # (plugin clones, caches); only Git-visible files are repo-owned config.
    directory = target if target.is_dir() else target.parent
    inside = subprocess.run(["git", "-C", str(directory), "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    if inside.returncode == 0 and inside.stdout.strip() == "true":
        listed = subprocess.run(["git", "-C", str(directory), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", str(target)],
                                check=True, capture_output=True, text=True).stdout
        return {directory / name for name in listed.split("\0") if name}
    # Flake sources are already Git-filtered; any other tree has no ownership boundary.
    assert target.is_relative_to("/nix/store"), f"live link target is neither a Git checkout nor store source: {target}"
    return set(target.rglob("*")) if target.is_dir() else {target}
def repo_config_sources():
    sources = set()
    allowed = {".zshenv", ".zprofile", ".zshrc", ".tmux.conf", ".hushlogin", ".npmrc", ".claude/statusline-command.sh", ".codex/rules"}
    for path in generated.rglob("*"):
        if not path.is_symlink(): continue
        target = resolve(path)
        checkout = next((root for _, root in mappings if target.is_relative_to(root)), None)
        if checkout is None: continue
        relative = target.relative_to(checkout)
        if relative.parts and relative.parts[:2] != (".config", "xj_raycast_scripts") and (relative.parts[0] in (".config", "config") or relative.as_posix() in allowed):
            sources.update(owned_files(target))
    return {path for path in sources if path.is_file()}
visit(generated)
tmux_config = resolve(generated / ".config/tmux/tmux.conf").read_text()
tmux_user_config = resolve(generated / ".config/tmux/user.conf")
provider_line = next(line for line in tmux_config.splitlines() if line.startswith("set-environment -g PATH "))
user_source_line = next(line for line in tmux_config.splitlines() if line.startswith("source-file ") and line.endswith("/tmux/user.conf"))
server_paths = shlex.split(provider_line)[3].split(":")
assert str((generation / "home-path").resolve() / "bin") in server_paths, "tmux must use its generation's tools"
assert all(path.startswith("/nix/store/") for path in server_paths[:3]), "pin Bash/tmux/profile before fallbacks"
if "\nrun-shell" in tmux_config:
    assert tmux_config.index(provider_line) < tmux_config.index("\nrun-shell"), "set server providers before plugins"
    assert tmux_config.index("\nrun-shell") < tmux_config.index(user_source_line), "preserve plugin-before-user-config order"
assert tmux_user_config.name == ".tmux.conf" and tmux_user_config.is_file(), "generated tmux config must source the live repo config"
tmux, socket = generation / "home-path/bin/tmux", "generated-links-" + str(os.getpid())
subprocess.run([tmux, "-L", socket, "-f", "/dev/null", "new-session", "-d", "sleep", "30"], check=True)
try:
    subprocess.run([tmux, "-L", socket, "source-file", "-n", tmux_user_config], check=True)
finally:
    subprocess.run([tmux, "-L", socket, "kill-server"], check=False, capture_output=True)
for relative in (".claude/settings.json", ".codex/config.toml", ".codex/hooks.json"):
    assert not (generated / relative).exists(), f"mutable target is owned by home.file: {relative}"
parsed = 0
toml_files = []
for path in sorted(set(generated.rglob("*")) | repo_config_sources()):
    if not path.is_file():
        continue
    resolved = resolve(path)
    suffix = resolved.suffix.lower()
    if suffix == ".json":
        json.loads(resolved.read_text())
        parsed += 1
    elif suffix in (".yaml", ".yml"):
        subprocess.run(["ruby", "-ryaml", "-e", "YAML.safe_load(File.read(ARGV[0]), aliases: true)", str(resolved)], check=True)
        parsed += 1
    elif suffix == ".toml":
        toml_files.append(resolved)
    elif resolved.name in (".zshenv", ".zprofile", ".zshrc") or suffix == ".zsh":
        subprocess.run([str(generation / "home-path/bin/zsh"), "-n", str(resolved)], check=True)
        parsed += 1
if toml_files:
    expression = "map (path: builtins.fromTOML (builtins.readFile path)) [ " + " ".join(
        json.dumps(str(path)) for path in toml_files) + " ]"
    subprocess.run(["nix", "--extra-experimental-features", "nix-command flakes", "eval", "--json", "--impure", "--expr", expression], check=True, stdout=subprocess.DEVNULL)
    parsed += len(toml_files)
with tempfile.TemporaryDirectory(prefix="generated-shell-") as directory:
    fixture = Path(directory)
    (fixture / ".zshenv").write_text(resolve(generated / ".zshenv").read_text())
    profile_text = resolve(generated / ".zprofile").read_text()
    (fixture / ".zprofile").write_text(profile_text.replace("/bin/launchctl setenv", "/usr/bin/true"))
    (fixture / ".zshrc").write_text("source " + shlex.quote(str(resolve(generated / ".zshrc"))) + "\n")
    private = fixture / ".config/zsh/private.zshenv"
    private.parent.mkdir(parents=True)
    private.write_text('export PATH="$HOME/fixture-private:$PATH"\nprint -r -- loaded >> "$HOME/private-loads"\n')
    generated_env = fixture / ".config/xj/zsh/home-manager.generated.zsh"
    generated_env.parent.mkdir(parents=True)
    generated_env.write_text(resolve(generated / ".config/xj/zsh/home-manager.generated.zsh").read_text())
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
    nested = subprocess.run(["/bin/zsh", "-lc", "/bin/zsh -lc 'print -r -- \"$PATH\"'"], env=env, check=True, capture_output=True, text=True)
    assert nested.stdout.strip() == observed[0], "nested login shell changed provider order"
print(f"generated state: links resolve, mutable targets excluded, shell provider order verified, {parsed} configs parsed")
