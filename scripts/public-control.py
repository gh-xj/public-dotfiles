#!/usr/bin/env python3
"""Explicit source/generation/runtime reconciliation. Output contains no raw hooks or argv."""
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
PUBLIC_TARGETS = set(MUTABLE) | {
    ".config/ghostty/config", ".config/tmux/tmux.conf", ".tmux.conf", ".zshenv", ".zshrc", ".zprofile",
    ".claude/statusline-command.sh", ".claude/CLAUDE.md", ".codex/AGENTS.md", "AGENTS.md",
    ".config/public-dotfiles/generation.json", ".local/bin/agent-pane-title", ".local/bin/agent-session",
    ".local/bin/agent-workmux-status", ".local/bin/agent-workspace",
}
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]


class SafeError(Exception):
    """Only fixed, public messages may be placed in this exception."""


class PublicParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse normally repeats the rejected value, which can be a private
        # profile path or an accidentally pasted credential.
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


def target_label(name):
    return name if name in PUBLIC_TARGETS else "<managed-target:" + hashlib.sha256(name.encode()).hexdigest()[:12] + ">"


def resolve(path):
    try:
        return path.resolve(strict=True)
    except (OSError, RuntimeError):
        return None


def metadata(generation):
    if generation is None:
        return {}
    return read_json(generation / "home-files/.config/public-dotfiles/generation.json")


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
                    if not re.fullmatch(r"agent-(?:session (?:claude|codex) (?:start|end)|workmux-status (?:working|waiting|done|resume))", hook.get("command", "")):
                        continue  # Never disclose arbitrary commands, even from a locally edited seed.
                    if hook["command"] not in commands:
                        plan.append({"action": "add-public-hook-preserving-others", "event": event, "command": hook["command"]})
            for legacy in ("workmux set-window-status working", "workmux set-window-status waiting", "workmux set-window-status done"):
                if legacy in commands:
                    plan.append({"action": "review-removal-of-legacy-public-status-hook", "event": event, "command": legacy})
        if provider == "claude":
            statusline = live.get("statusLine", {})
            desired_statusline = {"type": "command", "command": 'bash "$HOME/.claude/statusline-command.sh"'}
            if not isinstance(statusline, dict) or statusline.get("command") != desired_statusline["command"]:
                plan.append({"action": "add-statusline" if not statusline else "review-statusline-integration",
                             "desired": desired_statusline})
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


def tmux_options(config):
    options = {}
    try:
        for line in config.read_text().splitlines():
            args = shlex.split(line, comments=True)
            if args and args[0] in ("set", "setw", "set-option", "set-window-option") and len(args) >= 3:
                if args[-2] in ("pane-border-format", "pane-border-status"):
                    options[args[-2]] = args[-1]
    except (OSError, ValueError):
        pass
    return options


def disk_health(path):
    try:
        usage = shutil.disk_usage(path)
        return {"free_bytes": usage.free, "free_percent": round(100 * usage.free / usage.total, 2),
                "used_percent": round(100 * usage.used / usage.total, 2)}
    except OSError:
        return {"state": "unavailable"}


HEALTH_DEFAULTS = {"clients": 6, "agent_panes": 24, "panes": 40, "disk_use": 90,
                   "long_seconds": 600, "long_cpu": 20, "top": 10}


def elapsed_seconds(text):
    days, _, clock = text.rpartition("-")
    try:
        parts = list(map(int, clock.split(":")))
        seconds = 0
        for part in parts:
            seconds = seconds * 60 + part
        return seconds + (int(days) * 86400 if days else 0)
    except ValueError:
        return 0


def process_snapshot(runner=run):
    env = dict(os.environ, LC_ALL="C")
    stats = runner(["ps", "-axo", "pid=,pcpu=,etime=,comm="], env=env)
    argv = runner(["ps", "-ww", "-axo", "pid=,args="], env=env)
    if stats.returncode or argv.returncode:
        return None
    arguments = {}
    for line in argv.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[0].isdigit():
            arguments[int(fields[0])] = fields[1]
    processes = []
    for line in stats.stdout.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4:
            continue
        pid, cpu, elapsed, executable = fields
        try:
            pid, cpu = int(pid), float(cpu)
        except ValueError:
            continue
        name = Path(executable).name.lower()
        args = arguments.get(pid, "")
        provider = None
        if name == "codex" and not re.search(r"\b(?:app-server|exec-server|daemon|mcp-server)\b", args):
            provider = "Codex"
        elif (name == "claude" and ".app/" not in executable) or "/claude/versions/" in executable:
            provider = "Claude"
        kind = None
        if name in ("rg", "ripgrep", "find") or name == "grep" and re.search(r"\s-[^\s]*[rR]", args):
            kind = "search"
        elif name in ("pytest", "py.test", "jest", "vitest", "ctest") or name in ("go", "cargo", "node", "python", "python3") and re.search(r"\b(?:test|pytest|unittest|jest|vitest)\b", args):
            kind = "test"
        elif name in ("make", "gmake", "ninja", "cmake", "cargo", "rustc", "clang", "clang++", "gcc", "go", "nix"):
            kind = "build"
        # Discard executable paths and argv here, before any reporting function.
        processes.append({"pid": pid, "cpu_percent": cpu, "elapsed_seconds": elapsed_seconds(elapsed),
                          "provider": provider, "kind": kind,
                          "terminal": "tmux" if name.startswith("tmux") else "Ghostty" if name == "ghostty" else None})
    return processes


def tmux_snapshot(runner=run):
    clients = runner(["tmux", "list-clients", "-F", "#{client_termname}"])
    sessions = runner(["tmux", "list-sessions", "-F", "#{session_id}"])
    windows = runner(["tmux", "list-windows", "-a", "-F", "#{window_id}"])
    panes = runner(["tmux", "list-panes", "-a", "-F", "#{pane_id}\t#{?@codex_sid,1,0}\t#{?@claude_sid,1,0}\t#{@workmux_pane_status}"])
    if any(value.returncode for value in (clients, sessions, windows, panes)):
        return {"state": "unavailable"}
    unique_panes = {}
    for line in panes.stdout.splitlines():
        fields = line.split("\t", 3)
        if len(fields) == 4 and re.fullmatch(r"%\d+", fields[0]):
            unique_panes[fields[0]] = fields[1:]
    states = {"working": 0, "waiting": 0, "done": 0, "unknown": 0, "no_status": 0}
    icons = {"🤖": "working", "💬": "waiting", "✅": "done", "working": "working", "waiting": "waiting", "done": "done", "": "no_status"}
    for _, _, status in unique_panes.values():
        states[icons.get(status.strip(), "unknown")] += 1
    states.update(active=states["working"] + states["waiting"], finished=states["done"])
    return {"state": "observed", "clients": len(clients.stdout.splitlines()),
            "ghostty_clients": sum("ghostty" in name.lower() for name in clients.stdout.splitlines()),
            "sessions": len(set(sessions.stdout.splitlines())), "windows": len(set(windows.stdout.splitlines())),
            "panes": len(unique_panes), "agent_panes": sum(a == "1" or b == "1" for a, b, _ in unique_panes.values()),
            "workmux": states}


def workspace_report(topology, processes, disk, generations, thresholds):
    warnings = []
    for key, code in (("clients", "attached-client-count"), ("agent_panes", "agent-pane-count"), ("panes", "total-pane-count")):
        if topology.get(key, 0) > thresholds[key]:
            warnings.append(code)
    if disk.get("used_percent", 0) > thresholds["disk_use"]:
        warnings.append("disk-use")
    long_running = []
    providers = {"Claude": 0, "Codex": 0}
    terminal_cpu = {"tmux": 0.0, "Ghostty": 0.0}
    terminal_processes = {"tmux": 0, "Ghostty": 0}
    for process in processes or []:
        if process["provider"] in providers:
            providers[process["provider"]] += 1
        terminal = process["terminal"]
        if terminal:
            terminal_cpu[terminal] += process["cpu_percent"]
            terminal_processes[terminal] += 1
        if process["kind"] and process["elapsed_seconds"] > thresholds["long_seconds"] and process["cpu_percent"] >= thresholds["long_cpu"]:
            long_running.append({key: process[key] for key in ("pid", "kind", "cpu_percent", "elapsed_seconds")})
    if long_running:
        warnings.append("long-running-high-cpu-workload")
    drift = generations.get("active_matches_desired")
    if drift is False or generations.get("active_source_matches_checkout") is False:
        warnings.append("active-generation-drift")
    long_running.sort(key=lambda item: item["cpu_percent"], reverse=True)
    gaps = []
    if topology.get("state") != "observed":
        gaps.append("tmux-snapshot-unavailable")
    if processes is None:
        gaps.append("process-snapshot-unavailable")
    if "used_percent" not in disk:
        gaps.append("disk-snapshot-unavailable")
    if drift is None and generations.get("active_source_matches_checkout") is None:
        gaps.append("generation-comparison-unavailable; select --flake for evaluation")
    return {"mode": "read-only-single-snapshot", "thresholds": thresholds, "warnings": warnings,
            "observation_gaps": gaps,
            "tmux": topology, "provider_cli_processes": providers if processes is not None else None,
            "terminal_processes": terminal_processes if processes is not None else None,
            "terminal_cpu_percent": {k: round(v, 2) for k, v in terminal_cpu.items()} if processes is not None else None,
            "long_running_workloads": long_running[:thresholds["top"]],
            "additional_long_running_count": max(0, len(long_running) - thresholds["top"]),
            "disk": disk, "generations": generations,
            "follow_up": ["task doctor -- --live", "Review workload ownership manually; no process or pane is terminated."]}


class Control:
    def __init__(self, repo, home, flake=None, generation=None, runner=run):
        self.repo, self.home = repo.resolve(), home.absolute()
        self.flake = flake
        self.desired = generation.resolve() if generation else None
        self.run = runner
        self.target_home = None
        profile = home / ".local/state/nix/profiles/home-manager"
        if home == Path.home():
            profile = Path(os.getenv("PUBLIC_DOTFILES_ACTIVE_PROFILE", str(Path(os.getenv("XDG_STATE_HOME", str(home / ".local/state"))) / "nix/profiles/home-manager")))
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

    def select(self, build=False):
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
        if build and self.target_home.resolve() != self.home.resolve():
            raise SafeError("selected-profile-targets-another-home; refusing build and activation")
        if build and not self.desired.exists():
            built = self.run([*NIX, "build", "--no-write-lock-file", "--no-link", "--print-out-paths", attr + ".activationPackage"], timeout=1800)
            if built.returncode or built.stdout.strip() != str(self.desired):
                raise SafeError("selected-profile-build-failed-or-changed; rerun diagnosis")

    def generations(self):
        active_meta, desired_meta = metadata(self.active), metadata(self.desired)
        source = self.source()
        return {"source": source, "active_generation": generation_label(self.active),
                "selected_profile_targets_current_home": self.target_home.resolve() == self.home.resolve() if self.target_home else None,
                "desired_generation": generation_label(self.desired),
                "desired_built": self.desired.exists() if self.desired else None,
                "active_matches_desired": self.active == self.desired if self.active and self.desired else None,
                "active_source_revision": revision(active_meta.get("source_revision")),
                "desired_source_revision": revision(desired_meta.get("source_revision")),
                "active_source_fingerprint": revision(active_meta.get("source_fingerprint")),
                "desired_source_fingerprint": revision(desired_meta.get("source_fingerprint")),
                "active_source_matches_checkout": active_meta.get("source_revision") == source["revision"] and source["dirty"] is False
                    if revision(active_meta.get("source_revision")) and source["revision"] else None}

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
        # Ghostty can create a template when all config files are absent. Avoid
        # invoking it in that state: a doctor must not create runtime files.
        standard_lookup = env is not None or Path(os.getenv("XDG_CONFIG_HOME", str(self.home / ".config"))).resolve() == (self.home / ".config").resolve()
        valid = self.run([binary, "+validate-config"], env=env) if (parent / "config").is_file() and standard_lookup else None
        return {"parent": kind, "config_exists": (parent / "config").is_file(),
                "matches_active_generation": expected is not None and expected == target,
                "validation": "not-run-missing-or-nonstandard-config" if valid is None else "passed" if valid.returncode == 0 else "failed-or-unavailable",
                "running_surface_settings": "not-observable-from-config-file"}

    def doctor(self, live=False):
        report = self.generations()
        report["selection"] = "explicit" if self.flake else "provide --flake or PUBLIC_DOTFILES_HOME_FLAKE to compare selected profile"
        if live:
            report.update(ghostty=self.ghostty(), tmux=self.tmux(), integrations=integration_plan(self.home, self.repo),
                          generated_links=link_health(self.home, self.active), disk=disk_health(Path("/System/Volumes/Data") if Path("/System/Volumes/Data").exists() else self.home),
                          mutable_link_migrations=self.detached())
        return report

    def workspace(self, thresholds):
        volume = Path("/System/Volumes/Data")
        return workspace_report(tmux_snapshot(self.run), process_snapshot(self.run),
                                disk_health(volume if volume.exists() else self.home), self.generations(), thresholds)

    def plan(self):
        if not self.flake or not self.desired or not self.desired.is_dir():
            raise SafeError("reconcile requires an explicitly selected, built --flake PATH#HOME_PROFILE")
        if self.target_home is None or self.target_home.resolve() != self.home.resolve():
            raise SafeError("selected-profile-targets-another-home; refusing activation")
        for name in self.mutable_targets():
            if os.path.lexists(self.desired / "home-files" / name):
                raise SafeError("selected-profile-still-manages-mutable-agent-files; remove those Home Manager file declarations first")
        migration = self.run(["zsh", self.repo / "scripts/migrate-ghostty-parent.zsh", "--home", self.home, "--repo", self.repo, "--dry-run"])
        if migration.returncode:
            raise SafeError("Ghostty-parent-migration-blocked; inspect its parent symlink with the migration tool")
        mutable = self.detached()
        if any(x["action"].startswith("manual-review") for x in mutable):
            raise SafeError("unmanaged-mutable-config-symlink; resolve ownership explicitly before reconcile")
        paths, truncated = leaves(self.desired / "home-files")
        if truncated:
            raise SafeError("generated-link-plan-exceeds-bound; inspect selected profile before activation")
        changes = []
        for name, path in paths.items():
            if resolve(path) is None:
                raise SafeError("selected-generation-has-broken-links; restore required sources before reconcile")
            if resolve(path) != resolve(self.home / name) or resolve(path) is None:
                changes.append({"target": target_label(name), "operation": "install-generation-link"})
        old_paths, old_truncated = leaves(self.active / "home-files") if self.active else ({}, False)
        if old_truncated:
            raise SafeError("active-link-plan-exceeds-bound; inspect selected profile")
        for name, path in old_paths.items():
            if name not in paths and name not in MUTABLE and (self.home / name).is_symlink() and resolve(self.home / name) == resolve(path):
                changes.append({"target": target_label(name), "operation": "remove-obsolete-managed-link"})
        seed_missing = [name for name in self.mutable_targets() if not (self.home / name).exists()]
        needs_activation = self.active != self.desired or bool(changes or mutable or seed_missing or migration.stdout.strip())
        steps = []
        if migration.stdout.strip():
            steps.append("migrate-known-Ghostty-parent-or-create-real-directory")
        if mutable:
            steps.append("detach-known-mutable-agent-links-preserving-bytes")
        if needs_activation:
            steps.append("activate-selected-Home-Manager-generation")
        tmux = self.tmux()
        if tmux["state"] == "running" and (needs_activation or tmux["reload_needed"]):
            steps.append("reload-tmux-from-live-~/.tmux.conf")
        def ghostty_command(gen):
            if not gen:
                return None
            try:
                return next((line for line in (gen / "home-files/.config/ghostty/config").read_text().splitlines() if line.startswith("command = ")), None)
            except OSError:
                return None
        return {"mode": "dry-run", "generation": generation_label(self.desired), "steps": steps,
                "managed_link_changes": changes, "seed_only_when_missing": seed_missing,
                "mutable_link_migrations": mutable, "manual_merge_plan": integration_plan(self.home, self.repo),
                "ghostty_command_changed": ghostty_command(self.active) != ghostty_command(self.desired),
                "ghostty_follow_up": "reload config; use a new surface or manually restart when command changes",
                "tmux_restart_recommended": tmux["restart_recommended"],
                "other_activation_actions": "selected-profile-declared-package/service/activation-actions; no process termination by reconcile"}

    def apply(self, plan):
        # Execute exactly the operation list produced above. No merges, restarts,
        # kills, backup flags or git actions are hidden in this path.
        steps = plan["steps"]
        if any(step.startswith("migrate-known") for step in steps):
            result = self.run(["zsh", self.repo / "scripts/migrate-ghostty-parent.zsh", "--home", self.home, "--repo", self.repo, "--apply"])
            if result.returncode:
                raise SafeError("Ghostty-migration-failed; activation-not-started")
        if "detach-known-mutable-agent-links-preserving-bytes" in steps:
            self.detached(apply=True)
        if "activate-selected-Home-Manager-generation" in steps:
            result = self.run([self.desired / "activate"], timeout=1800)
            if result.returncode:
                raise SafeError("Home-Manager-activation-failed; inspect selected profile locally; tmux-not-reloaded")
        if "reload-tmux-from-live-~/.tmux.conf" in steps:
            result = self.run(["tmux", "source-file", self.home / ".tmux.conf"])
            if result.returncode:
                raise SafeError("tmux-reload-failed; activation-completed; reload-manually")
        return dict(plan, mode="applied", manual_merge_plan=integration_plan(self.home, self.repo),
                    mutable_policy="preserve-existing; seed-only-if-missing; no-private-hook-merge")


def main():
    parser = PublicParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--home", type=Path, default=Path.home())
    sub = parser.add_subparsers(dest="command", required=True)
    doctor = sub.add_parser("doctor")
    doctor.add_argument("--live", action="store_true")
    doctor.add_argument("--generation", type=Path, help="already built comparison generation (read-only)")
    workspace = sub.add_parser("workspace")
    workspace.add_argument("action", choices=["doctor"])
    workspace.add_argument("--generation", type=Path, help="already built comparison generation")
    workspace.add_argument("--flake", help="opt into selected-profile evaluation (no build)")
    for key, default in HEALTH_DEFAULTS.items():
        workspace.add_argument("--" + ("top" if key == "top" else "warn-" + key.replace("_", "-")), type=int, default=default, dest=key)
    reconcile = sub.add_parser("reconcile")
    modes = reconcile.add_mutually_exclusive_group(required=True)
    modes.add_argument("--dry-run", action="store_true")
    modes.add_argument("--apply", action="store_true")
    for command in (doctor, reconcile):
        command.add_argument("--flake", default=os.getenv("PUBLIC_DOTFILES_HOME_FLAKE"))
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
            if args.command == "reconcile" and args.home.resolve() != Path.home().resolve():
                raise SafeError("reconcile-only-applies-to-current-home; alternate-home is read-only diagnosis")
            control = Control(args.repo, args.home, args.flake, getattr(args, "generation", None))
            control.select(build=args.command == "reconcile")
            if args.command == "doctor":
                report = control.doctor(args.live)
            elif args.command == "workspace":
                thresholds = {key: getattr(args, key) for key in HEALTH_DEFAULTS}
                if any(value < 0 for value in thresholds.values()) or not 1 <= thresholds["top"] <= 50 or thresholds["disk_use"] > 100:
                    raise SafeError("invalid-health-thresholds; use nonnegative values, disk <=100 and top between 1 and 50")
                report = control.workspace(thresholds)
            else:
                report = control.plan()
                if args.apply:
                    report = control.apply(report)
        print(json.dumps(report, indent=2, ensure_ascii=False))
    except SafeError as error:
        parser.exit(1, str(error) + "\n")
    except (OSError, ValueError, TypeError, KeyError, RuntimeError):
        parser.exit(1, "invalid-or-unavailable-state; inspect the selected profile/config locally (private details suppressed)\n")


if __name__ == "__main__":
    main()
