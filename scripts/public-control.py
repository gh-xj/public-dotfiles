#!/usr/bin/env python3
"""Read-only source, generated-output and runtime diagnosis."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

MUTABLE = (".claude/settings.json", ".codex/config.toml", ".codex/hooks.json")
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]


class SafeError(Exception):
    """Only fixed, public messages may be placed in this exception."""


class PublicParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "invalid arguments; use --help for supported public options\n")


def run(argv, timeout=15, **kwargs):
    try:
        return subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=timeout, **kwargs)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess([], 124, "", "")


def read_json(path, invalid=None):
    fallback = {} if invalid is None else invalid
    try:
        if path.stat().st_size > 4 * 1024 * 1024:
            return fallback
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else fallback
    except (OSError, ValueError):
        return fallback


def revision(value):
    return value if isinstance(value, str) and re.fullmatch(r"[0-9a-f]{7,64}(?:-dirty)?", value) else None


def generation_label(path):
    if path is None:
        return None
    text = str(path)
    return text if re.fullmatch(r"/nix/store/[0-9a-z]{32}-home-manager-generation", text) else "<nonstandard-generation>"


def resolve(path):
    if path is None:
        return None
    try:
        return path.resolve(strict=True)
    except (OSError, RuntimeError):
        return None


def metadata(generation):
    return read_json(generation / "home-files/.config/public-dotfiles/generation.json") if generation else {}


def detach_mutable(home, repo, apply=False, skip=()):
    """Detach only known managed links, preserving bytes before HM cleans old links."""
    actions = []
    for name in MUTABLE:
        if name in skip:
            continue
        path = home / name
        if path.parent.is_symlink() or path.parent.resolve().is_relative_to(repo.resolve()):
            if apply:
                raise SafeError("mutable-agent-parent-is-symlink; resolve its ownership before activation")
            actions.append({"target": name, "action": "manual-review-agent-parent-symlink"})
            continue
        if not path.is_symlink():
            continue
        raw = os.readlink(path)
        destination = (path.parent / raw).resolve()
        known = raw.startswith("/nix/store/") or destination in {
            repo / ".claude/settings.json", repo / "config/claude/settings.json",
            repo / "config/codex/config.toml", repo / "config/codex/hooks.json",
        }
        if not known:
            actions.append({"target": name, "action": "manual-review-unmanaged-symlink"})
            continue
        if not path.is_file():
            actions.append({"target": name, "action": "seed-missing-managed-target"})
            continue
        actions.append({"target": name, "action": "detach-managed-link-preserve-bytes"})
        if apply:
            content = path.read_bytes()
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
                tmp.write(content)
                tmp.flush()
                os.fsync(tmp.fileno())
                temp_path = Path(tmp.name)
            try:
                if not path.is_symlink() or os.readlink(path) != raw or path.read_bytes() != content:
                    raise SafeError("mutable-config-changed-during-detach; retry after the writer finishes")
                os.replace(temp_path, path)
            finally:
                temp_path.unlink(missing_ok=True)
    return actions


def integration_plan(home, repo):
    result = {}
    for provider, relative, seed in (
        ("claude", ".claude/settings.json", "config/claude/settings.json"),
        ("codex", ".codex/hooks.json", "config/codex/hooks.json"),
    ):
        path = home / relative
        live, wanted = read_json(path, invalid=False), read_json(repo / seed)
        plan = []
        if not wanted:
            result[provider] = {"state": "public-seed-unavailable", "merge_plan": []}
            continue
        if path.exists() and live is False:
            result[provider] = {"state": "invalid-json-review-manually", "merge_plan": []}
            continue
        if live is False:
            live = {}
        hooks = live.get("hooks", {})
        if not isinstance(hooks, dict):
            result[provider] = {"state": "invalid-hook-structure-review-manually", "merge_plan": []}
            continue
        for event, groups in wanted.get("hooks", {}).items():
            if event not in ("SessionStart", "SessionEnd", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop"):
                continue
            current = hooks.get(event, [])
            commands = {item.get("command") for group in current if isinstance(group, dict) and not group.get("matcher")
                        for item in group.get("hooks", []) if isinstance(item, dict) and item.get("type") == "command"
                        and isinstance(item.get("command"), str)} if isinstance(current, list) else set()
            for group in groups:
                for hook in group["hooks"]:
                    command = hook.get("command", "")
                    if re.fullmatch(r"agent-(?:session (?:claude|codex) (?:start|end)|workmux-status (?:working|waiting|done|resume))", command) and command not in commands:
                        plan.append({"action": "add-public-hook-preserving-others", "event": event, "command": command})
            for legacy in ("workmux set-window-status working", "workmux set-window-status waiting", "workmux set-window-status done"):
                if legacy in commands:
                    plan.append({"action": "review-removal-of-legacy-public-status-hook", "event": event, "command": legacy})
        if provider == "claude":
            statusline = live.get("statusLine", {})
            desired = {"type": "command", "command": 'bash "$HOME/.claude/statusline-command.sh"'}
            if not isinstance(statusline, dict) or statusline.get("command") != desired["command"]:
                plan.append({"action": "add-statusline" if not statusline else "review-statusline-integration", "desired": desired})
            if isinstance(statusline, dict) and "refreshInterval" in statusline:
                plan.append({"action": "review-periodic-statusline-refresh", "default": "event-driven", "opt_in_seconds": 30})
        result[provider] = {"state": "missing" if not path.exists() else "present", "merge_plan": plan}
    return result


def leaves(root, limit=4096):
    result = {}
    if not root.exists():
        return result, False
    for directory, dirs, files in os.walk(root, followlinks=False):
        links = [name for name in dirs if (Path(directory) / name).is_symlink()]
        for name in files + links:
            path = Path(directory) / name
            result[str(path.relative_to(root))] = path
            if len(result) >= limit:
                return result, True
    return result, False


def link_health(home, generation):
    if generation is None:
        return {"state": "no-generation"}
    paths, truncated = leaves(generation / "home-files")
    broken = missing = different = 0
    for relative, path in paths.items():
        wanted = resolve(path)
        live = resolve(home / relative)
        broken += wanted is None
        missing += live is None
        different += live is not None and live != wanted
    return {"checked": len(paths), "broken_generated": broken, "missing_live": missing,
            "different_live": different, "truncated": truncated}


def generated_fingerprint(generation, limit=10000):
    """Hash generated file contents, not checkout revision or store-path names."""
    if generation is None or not generation.is_dir():
        return None
    digest = hashlib.sha256()
    visited = 0

    def add(path, logical, ancestors=()):
        nonlocal visited
        visited += 1
        if visited > limit:
            raise RuntimeError("generated output exceeds fingerprint bound")
        try:
            if path.is_symlink():
                target = path.resolve(strict=True)
                if target in ancestors:
                    digest.update(b"loop\0" + logical.encode() + b"\0")
                    return
                add(target, logical, (*ancestors, target))
            elif path.is_dir():
                digest.update(b"dir\0" + logical.encode() + b"\0")
                for child in sorted(path.iterdir(), key=lambda item: item.name):
                    add(child, logical + "/" + child.name, ancestors)
            elif path.is_file():
                digest.update(b"file\0" + logical.encode() + b"\0")
                with path.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
            else:
                digest.update(b"other\0" + logical.encode() + b"\0")
        except (OSError, RuntimeError):
            digest.update(b"unavailable\0" + logical.encode() + b"\0")

    add(generation / "home-files", "home-files")
    add(generation / "activate", "activate")
    return digest.hexdigest()


def tmux_options(config):
    options = {}
    try:
        lines = config.read_text().splitlines()
    except OSError:
        return options
    for line in lines:
        command = line.split(maxsplit=1)
        if not command or command[0] not in ("set", "setw", "set-option", "set-window-option"):
            continue
        try:
            args = shlex.split(line, comments=True)
        except ValueError:
            continue
        if len(args) >= 3 and args[-2] in ("pane-border-format", "pane-border-status"):
            options[args[-2]] = args[-1]
    return options


class Control:
    def __init__(self, repo, home, flake=None, generation=None, runner=run):
        self.repo, self.home = repo.resolve(), home.absolute()
        self.flake, self.desired, self.run = flake, generation.resolve() if generation else None, runner
        self.target_home = None
        profile = home / ".local/state/nix/profiles/home-manager"
        if home == Path.home():
            state = Path(os.getenv("XDG_STATE_HOME", str(home / ".local/state")))
            profile = Path(os.getenv("PUBLIC_DOTFILES_ACTIVE_PROFILE", str(state / "nix/profiles/home-manager")))
        self.active = resolve(profile)

    def source(self):
        prefix = ["git", "--no-optional-locks", "-C", self.repo]
        dirty = self.run(prefix + ["status", "--short"])
        head = self.run(prefix + ["rev-parse", "HEAD"])
        main = self.run(prefix + ["rev-parse", "refs/remotes/origin/main"])
        return {"revision": revision(head.stdout.strip()), "origin_main_revision": revision(main.stdout.strip()),
                "dirty": bool(dirty.stdout.strip()) if dirty.returncode == 0 else None}

    def mutable_targets(self):
        manifest = metadata(self.desired if self.desired and self.desired.exists() else self.active)
        declared = manifest.get("mutable_targets", list(MUTABLE))
        return tuple(name for name in MUTABLE if name in declared)

    def detached(self, apply=False):
        return detach_mutable(self.home, self.repo, apply, skip=set(MUTABLE) - set(self.mutable_targets()))

    def select(self):
        if not self.flake:
            return
        ref, sep, profile = self.flake.rpartition("#")
        if not sep or not ref or not re.fullmatch(r"[A-Za-z0-9_.@-]+", profile):
            raise SafeError("select --flake PATH#HOME_PROFILE (or PUBLIC_DOTFILES_HOME_FLAKE)")
        attr = ref + "#homeConfigurations." + json.dumps(profile)
        expression = 'h: { generation = toString h.activationPackage; home = h.config.home.homeDirectory; }'
        evaluated = self.run([*NIX, "eval", "--no-write-lock-file", "--json", attr, "--apply", expression], timeout=120)
        if evaluated.returncode:
            raise SafeError("selected-profile-evaluation-failed; check the selected flake locally")
        values = json.loads(evaluated.stdout)
        self.desired, self.target_home = Path(values["generation"]), Path(values["home"])

    def generations(self):
        active_fingerprint = generated_fingerprint(self.active)
        desired_fingerprint = generated_fingerprint(self.desired)
        return {"source": self.source(), "active_generation": generation_label(self.active),
                "selected_profile_targets_current_home": self.target_home.resolve() == self.home.resolve() if self.target_home else None,
                "desired_generation": generation_label(self.desired),
                "desired_built": self.desired.exists() if self.desired else None,
                "active_output_fingerprint": active_fingerprint,
                "desired_output_fingerprint": desired_fingerprint,
                "active_matches_desired": active_fingerprint == desired_fingerprint
                    if active_fingerprint and desired_fingerprint else None}

    def tmux(self):
        probe = self.run(["tmux", "display-message", "-p", "#{version}"])
        if probe.returncode:
            return {"state": "no-accessible-server", "reload_needed": False, "restart_recommended": False}
        config = self.desired / "home-files/.config/tmux/tmux.conf" if self.desired and self.desired.exists() else self.repo / ".tmux.conf"
        expected = tmux_options(config)
        matches = bool(expected) and all(self.run(["tmux", "show-options", "-gv", key]).stdout.rstrip("\n") == val for key, val in expected.items())
        installed_generation = self.desired if self.desired and self.desired.exists() else self.active
        installed = self.run([installed_generation / "home-path/bin/tmux", "-V"]) if installed_generation else None
        return {"state": "running", "pane_border_matches": matches, "reload_needed": not matches,
                "restart_recommended": probe.stdout.strip() != installed.stdout.strip().removeprefix("tmux ")
                    if installed and installed.returncode == 0 else None}

    def ghostty(self):
        parent = self.home / ".config/ghostty"
        kind = "symlink" if parent.is_symlink() else "real-directory" if parent.is_dir() else "missing-or-file"
        expected = resolve(self.active / "home-files/.config/ghostty/config") if self.active else None
        target = resolve(parent / "config")
        binary = shutil.which("ghostty") or "/Applications/Ghostty.app/Contents/MacOS/ghostty"
        env = None if self.home == Path.home() else dict(os.environ, HOME=str(self.home), CFFIXED_USER_HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / ".config"))
        standard_lookup = env is not None or Path(os.getenv("XDG_CONFIG_HOME", str(self.home / ".config"))).resolve() == (self.home / ".config").resolve()
        valid = self.run([binary, "+validate-config"], env=env) if (parent / "config").is_file() and standard_lookup else None
        return {"parent": kind, "config_exists": (parent / "config").is_file(),
                "matches_active_generation": expected is not None and expected == target,
                "validation": "not-run-missing-or-nonstandard-config" if valid is None else "passed" if valid.returncode == 0 else "failed-or-unavailable",
                "running_surface_settings": "not-observable-from-config-file"}

    def doctor(self, live=False):
        report = self.generations()
        report["selection"] = "explicit" if self.flake or self.desired else "provide --flake or --generation to compare generated output"
        if live:
            report.update(programs=self.programs(), ghostty=self.ghostty(), tmux=self.tmux(), integrations=integration_plan(self.home, self.repo),
                          generated_links=link_health(self.home, self.active), mutable_link_migrations=self.detached())
        return report



    def programs(self):
        """Compare the paired Yazi commands with the selected/active generation."""
        generation = self.desired if self.desired and self.desired.exists() else self.active
        declared = metadata(generation).get("owned_programs", {})
        result = {}
        for name in ("yazi", "ya"):
            expected = generation / "home-path/bin" / name if generation else None
            runtime = Path(shutil.which(name)) if shutil.which(name) else None
            expected_path = resolve(expected) if expected else None
            runtime_path = resolve(runtime) if runtime else None
            specification = declared.get(name, {}) if isinstance(declared, dict) else {}
            if not isinstance(specification, dict):
                specification = {}
            version = specification.get("version")
            version = version if isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version) else None

            def probe(binary):
                if not binary:
                    return None
                output = self.run([binary, "--version"], timeout=5)
                match = re.search(r"\b\d+\.\d+\.\d+\b", output.stdout) if output.returncode == 0 else None
                return match.group(0) if match else None

            owner = None
            if runtime_path:
                text = str(runtime_path)
                owner = "nix" if text.startswith("/nix/store/") else "homebrew" if text.startswith(("/opt/homebrew/", "/usr/local/Cellar/")) else "other"
            result[name] = {
                "declared_owner": "nix" if specification.get("owner") == "nix" else None,
                "declared_version": version,
                "generation_version": probe(expected_path),
                "runtime_version": probe(runtime_path),
                "runtime_owner": owner,
                "matches_generation": expected_path == runtime_path if expected_path and runtime_path else None,
            }
        versions = [item["runtime_version"] for item in result.values()]
        return {"commands": result, "paired_runtime_versions_match": len(set(versions)) == 1 if all(versions) else None}

    def plan(self, scope="home", source_mode="working-tree"):
        if self.desired is None or not self.desired.exists():
            raise SafeError("plan-requires-built-generation; build the owning profile first")
        desired, truncated = leaves(self.desired / "home-files")
        active, _ = leaves(self.active / "home-files") if self.active else ({}, False)
        new = changed = same = repository = 0
        reloads = set()
        rules = {
            ".config/yazi": "Restart Yazi",
            ".config/nvim": "Restart Neovim",
            ".config/ghostty": "Reload Ghostty; use a new surface for startup-only settings",
            ".config/tmux": "Reload tmux config; check binary drift before restarting a server",
            ".zsh": "Open a new shell",
        }
        for relative, path in desired.items():
            target = resolve(path)
            live = resolve(self.home / relative)
            if target and not str(target).startswith("/nix/store/"):
                repository += 1
            differs = target != live
            if target and live and target.is_file() and live.is_file():
                differs = target.read_bytes() != live.read_bytes()
            if live is None:
                new += 1
            elif differs:
                changed += 1
            else:
                same += 1
            if live is None or differs:
                for prefix, message in rules.items():
                    if relative.startswith(prefix):
                        reloads.add(message)
        removed = len(set(active) - set(desired))
        programs = self.programs()
        if any(state["matches_generation"] is False for state in programs["commands"].values()):
            reloads.add("Open a new shell or rehash commands; restart Yazi after package changes")
        return {
            "scope": scope,
            "source_mode": source_mode,
            "source": self.source(),
            "files": {"new": new, "changed": changed, "same": same, "removed_from_declaration": removed,
                      "repo_links": repository, "truncated": truncated},
            "programs": programs,
            "activation_hooks": "Native activation hooks run only on apply; the file summary is not a simulation of their effects",
            "runtime_seeds": "Existing app-owned settings are preserved; review doctor integration suggestions separately",
            "repository_files": "Repo links can already reflect uncommitted edits; static snapshots use the selected source",
            "after_apply": sorted(reloads),
            "apply_command": "task -g dotfiles:apply" if scope == "home" else "no public system apply",
            "generation_changed": resolve(self.active) != resolve(self.desired),
        }


def print_plan(report):
    print("Scope: " + report["scope"] + (" (includes system settings; sudo is required for apply)" if report["scope"] == "system" else " (Home Manager; no sudo)"))
    print("Source: " + report["source_mode"])
    if report["source"]["dirty"]:
        print("Checkout has pending edits: " + ("snapshots ignore them; commit before apply" if report["source_mode"] == "committed-head" else "this standalone preview includes them"))
    files = report["files"]
    print(f"Files: {files['new']} new, {files['changed']} changed, {files['same']} already match, {files['removed_from_declaration']} removed from declarations")
    print(report["repository_files"])
    print(report["runtime_seeds"])
    print(report["activation_hooks"])
    for name, state in report["programs"]["commands"].items():
        print(f"{name}: declared {state['declared_version'] or 'unknown'}; runtime {state['runtime_version'] or 'unknown'} via {state['runtime_owner'] or 'unknown'}; matches generation={state['matches_generation']}")
    if report["after_apply"]:
        print("After apply: " + "; ".join(report["after_apply"]))
    else:
        print("After apply: config reload needs are app-specific; unchanged file bytes do not prove running apps reloaded")
    print("Apply: " + report["apply_command"])

def main():
    parser = PublicParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--home", type=Path, default=Path.home())
    sub = parser.add_subparsers(dest="command", required=True)
    doctor = sub.add_parser("doctor")
    doctor.add_argument("--live", action="store_true")
    doctor.add_argument("--generation", type=Path, help="already built comparison generation (read-only)")
    doctor.add_argument("--flake", default=os.getenv("PUBLIC_DOTFILES_HOME_FLAKE"))
    plan = sub.add_parser("plan", help="Preview a built native generation; never activate it")
    plan.add_argument("--generation", type=Path, required=True)
    plan.add_argument("--scope", choices=("home", "system"), default="home")
    plan.add_argument("--source-mode", choices=("working-tree", "committed-head"), default="working-tree")
    plan.add_argument("--json", action="store_true")
    detach = sub.add_parser("detach-agent-configs", help=argparse.SUPPRESS)
    detach_mode = detach.add_mutually_exclusive_group(required=True)
    detach_mode.add_argument("--dry-run", action="store_true")
    detach_mode.add_argument("--apply", action="store_true")
    detach.add_argument("--skip", action="append", choices=MUTABLE, default=[])
    args = parser.parse_args()
    try:
        if args.command == "detach-agent-configs":
            report = detach_mutable(args.home, args.repo.resolve(), apply=args.apply, skip=args.skip)
        else:
            control = Control(args.repo, args.home, getattr(args, "flake", None), args.generation)
            control.select()
            report = control.plan(args.scope, args.source_mode) if args.command == "plan" else control.doctor(args.live)
        if args.command == "plan" and not args.json:
            print_plan(report)
        else:
            print(json.dumps(report, indent=2, ensure_ascii=False))
    except SafeError as error:
        parser.exit(1, str(error) + "\n")
    except (OSError, ValueError, TypeError, KeyError, RuntimeError):
        parser.exit(1, "invalid-or-unavailable-state; inspect the selected profile/config locally (private details suppressed)\n")


if __name__ == "__main__":
    main()
