#!/usr/bin/env python3
"""Report missing or duplicate managed providers for declared commands on PATH."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

SYSTEM_DIRS = {"/usr/bin", "/bin", "/usr/sbin", "/sbin"}
MISE_COMMANDS = {
    "node": {"node", "npm", "npx", "corepack"},
    "go": {"go", "gofmt"},
    "rust": {"cargo", "rustc", "rustdoc", "rustfmt", "clippy-driver"},
    "bun": {"bun", "bunx"},
    "python": {"python", "python3"},
    "uv": {"uv", "uvx"},
    "npm:prettier": {"prettier"},
    "npm:@google/gemini-cli": {"gemini"},
    "npm:@googleworkspace/cli": {"gws"},
    "npm:@jackwener/opencli": {"opencli"},
    "npm:@jackwener/wx-cli": {"wx"},
    "npm:@larksuite/cli": {"lark-cli"},
    "npm:ccusage": {"ccusage"},
    "npm:markdownlint-cli2": {"markdownlint-cli2"},
}


def executables(directory):
    try:
        return {path.name for path in directory.iterdir() if path.is_file() and os.access(path, os.X_OK)}
    except OSError:
        return set()


def mise_tools(path):
    tools, active = {}, False
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return tools
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            active = stripped == "[tools]"
            continue
        if not active or not stripped or stripped.startswith("#"):
            continue
        match = re.match(r'("[^"]+"|[^= ]+)\s*=\s*"([^"]+)"', stripped)
        if match:
            tools[match.group(1).strip('"')] = match.group(2)
    return tools


def brew_commands(brewfile, brew):
    commands, missing = set(), []
    try:
        formulae = [match.group(1) for line in brewfile.read_text().splitlines()
                    if (match := re.match(r'\s*brew\s+"([^"]+)"', line))]
    except OSError:
        return commands, ["brewfile"]
    if not brew:
        return {name for name in formulae}, ["brew"]
    for formula in formulae:
        result = subprocess.run([brew, "--prefix", formula], capture_output=True, text=True, timeout=10)
        if result.returncode:
            missing.append("brew:" + formula)
            commands.add(formula)
            continue
        prefix = Path(result.stdout.strip())
        found = executables(prefix / "bin") | executables(prefix / "sbin")
        commands.update(found or {formula})
    return commands, missing


def label(directory, home, profile):
    text = str(directory)
    if directory == profile / "home-path/bin":
        return "home-manager"
    if directory == home / ".local/share/mise/shims":
        return "mise"
    if directory == home / ".local/bin":
        return "user-local"
    if directory in {home / "go/bin", home / ".cargo/bin", home / ".local/share/npm-global/bin", home / ".bun/bin"}:
        return "legacy-ecosystem"
    if text.startswith(("/opt/homebrew/", "/usr/local/")):
        return "homebrew"
    if text.startswith(("/etc/profiles/per-user/", "/run/current-system/")):
        return "nix-darwin"
    if text.startswith("/nix/var/nix/profiles/default/"):
        return "determinate-nix"
    return "other-managed"


def audit(home, profile, brewfile, mise_config, path_value):
    declared = {}
    for command in executables(profile / "home-path/bin"):
        declared.setdefault(command, set()).add("nix")
    brew = shutil.which("brew", path=path_value) or next((p for p in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew") if Path(p).is_file()), None)
    brew_declared, setup_missing = brew_commands(brewfile, brew)
    for command in brew_declared:
        declared.setdefault(command, set()).add("brew")
    for tool in mise_tools(mise_config):
        commands = MISE_COMMANDS.get(tool, {tool.rsplit(":", 1)[-1].rsplit("/", 1)[-1].removesuffix("-cli")})
        for command in commands:
            declared.setdefault(command, set()).add("mise")

    directories = []
    for value in path_value.split(os.pathsep):
        if value and value not in SYSTEM_DIRS:
            directory = Path(value).expanduser()
            if directory not in directories:
                directories.append(directory)
    issues = [(item, []) for item in setup_missing]
    for command, owners in sorted(declared.items()):
        providers = sorted({label(directory, home, profile) for directory in directories
                            if (directory / command).is_file() and os.access(directory / command, os.X_OK)})
        if len(providers) != 1:
            issues.append((command + " [" + ",".join(sorted(owners)) + "]", providers))
    return declared, issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--brewfile", type=Path, default=Path(__file__).resolve().parent.parent / "Brewfile")
    parser.add_argument("--mise-config", type=Path, default=Path(__file__).resolve().parent.parent / "config/mise/config.toml")
    parser.add_argument("--path", default=os.environ.get("PATH", ""))
    args = parser.parse_args()
    profile = args.profile or args.home / ".local/state/nix/profiles/home-manager"
    declared, issues = audit(args.home, profile, args.brewfile, args.mise_config, args.path)
    for command, providers in issues:
        state = "missing" if not providers else "duplicate: " + ", ".join(providers)
        print(f"{command}: {state}")
    print(f"command provenance: {len(declared)} declared commands, {len(issues)} issue(s)")
    raise SystemExit(bool(issues))


if __name__ == "__main__":
    main()
