#!/usr/bin/env python3
"""Control-plane fixtures: real migration, isolated fake activation, no user state."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("public_control", root / "scripts/public-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


def snapshot(root):
    return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink() else
            ("dir",) if p.is_dir() else ("file", p.read_bytes()) for p in root.rglob("*")}


with tempfile.TemporaryDirectory(prefix="reconcile-test-") as tmp:
    base = Path(tmp).resolve()
    repo, home, old, new = [base / name for name in ("checkout", "home", "old-generation", "new-generation")]
    repo.mkdir()
    (repo / "scripts").mkdir()
    for name in ("config/claude/settings.json", "config/codex/hooks.json", ".tmux.conf", "scripts/migrate-ghostty-parent.zsh"):
        target = repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
    for generation, revision in ((old, "a" * 40), (new, "b" * 40)):
        meta = generation / "home-files/.config/public-dotfiles/generation.json"
        meta.parent.mkdir(parents=True)
        meta.write_text(json.dumps({"source_revision": revision}))
        ghostty = generation / "home-files/.config/ghostty/config"
        ghostty.parent.mkdir(parents=True)
        ghostty.write_text("command = " + ("old-command" if generation == old else "new-command") + "\n")
        tmux = generation / "home-files/.config/tmux/tmux.conf"
        tmux.parent.mkdir(parents=True)
        shutil.copyfile(root / ".tmux.conf", tmux)
        (generation / "home-files/.tmux.conf").write_text("fixture tmux config")
    profile = home / ".local/state/nix/profiles/home-manager"
    profile.parent.mkdir(parents=True)
    profile.symlink_to(old)
    legacy = repo / ".config/ghostty"
    legacy.mkdir(parents=True)
    (home / ".config").mkdir()
    (home / ".config/ghostty").symlink_to(legacy)
    private_marker = "sensitive-fixture-command-do-not-print"
    live_claude = home / ".claude/settings.json"
    live_claude.parent.mkdir()
    live_claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": private_marker}]}]},
                                      "statusLine": {"type": "command", "command": private_marker, "refreshInterval": 5}}))
    live_codex = home / ".codex/config.toml"
    live_codex.parent.mkdir()
    live_codex.write_text('model_provider = "sensitive-fixture-provider"\n')
    # A legacy repo link is detached byte-for-byte, not replaced by the seed.
    hooks = home / ".codex/hooks.json"
    legacy_hooks = repo / "config/codex/hooks.json"
    legacy_hooks.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": private_marker}]}]}}))
    hooks.symlink_to(legacy_hooks)
    # Public seed stays separate in the test so the drift plan sees desired entries.
    missing_plan = control.integration_plan(home, root)
    assert missing_plan["claude"]["merge_plan"] and missing_plan["codex"]["merge_plan"]
    assert private_marker not in json.dumps(missing_plan)
    empty_home = base / "empty-settings"
    for relative in (".claude/settings.json", ".codex/hooks.json"):
        empty = empty_home / relative
        empty.parent.mkdir(parents=True, exist_ok=True)
        empty.write_text("{}")
    empty_plan = control.integration_plan(empty_home, root)
    assert all(value["state"] == "present" and value["merge_plan"] for value in empty_plan.values())
    (empty_home / ".claude/settings.json").write_text("not-json")
    assert control.integration_plan(empty_home, root)["claude"]["state"] == "invalid-json-review-manually"
    before_mutable = {name: (home / name).read_bytes() for name in control.MUTABLE}

    calls = []
    running_format = " #{window_name} "
    def runner(argv, **kwargs):
        global running_format
        argv = list(map(str, argv))
        calls.append(argv)
        code, out = 0, ""
        if argv[0] == "git":
            out = "" if "status" in argv else "b" * 40
        elif argv[0] == "nix":
            out = json.dumps({"generation": str(new), "home": str(home)})
        elif argv[0] == "zsh":
            return control.run(argv, **kwargs)
        elif argv[0] == "tmux":
            if argv[1] == "display-message":
                out = "3.7"
            elif argv[1] == "show-options":
                out = running_format if argv[-1] == "pane-border-format" else "top"
            elif argv[1] == "source-file":
                assert profile.resolve() == new
                running_format = control.tmux_options(new / "home-files/.config/tmux/tmux.conf")["pane-border-format"]
        elif argv[0].endswith("/bin/tmux"):
            out = "tmux 3.7"
        elif argv[0] == str(new / "activate"):
            assert not (home / ".config/ghostty").is_symlink()
            assert not hooks.is_symlink()
            for name, value in before_mutable.items():
                assert (home / name).read_bytes() == value
            for name, path in control.leaves(new / "home-files")[0].items():
                target = home / name
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.is_symlink():
                    target.unlink()
                target.symlink_to(path)
            profile.unlink()
            profile.symlink_to(new)
        else:
            assert "+validate-config" in argv
        return subprocess.CompletedProcess([], code, out, "sensitive-fixture-error-do-not-print")

    app = control.Control(repo, home, "fixture#test", runner=runner)
    app.select()
    report = app.doctor(live=True)
    assert report["active_matches_desired"] is False
    assert report["active_source_matches_checkout"] is False
    assert report["ghostty"]["parent"] == "symlink"
    assert report["tmux"]["reload_needed"] is True
    before = snapshot(base)
    plan = app.plan()
    assert snapshot(base) == before, "dry-run mutated home or repo"
    assert "activate-selected-Home-Manager-generation" in plan["steps"]
    assert "reload-tmux-from-live-~/.tmux.conf" in plan["steps"]
    assert plan["ghostty_command_changed"]
    output = json.dumps([report, plan])
    for forbidden in (private_marker, "sensitive-fixture-provider", "sensitive-fixture-error", str(home), str(repo)):
        assert forbidden not in output, "diagnostics leaked private fixture data"
    assert not any(a[0].endswith("/activate") or "source-file" in a or (a[0] == "zsh" and "--apply" in a) for a in calls)
    app.apply(plan)
    assert not (home / ".config/ghostty").is_symlink()
    assert (home / ".config/ghostty/config").resolve() == new / "home-files/.config/ghostty/config"
    assert not (legacy / "config").exists()
    assert hooks.is_file() and not hooks.is_symlink()
    for name, value in before_mutable.items():
        assert (home / name).read_bytes() == value
    fresh = control.Control(repo, home, "fixture#test", runner=runner)
    fresh.select()
    assert fresh.generations()["active_matches_desired"]
    assert fresh.tmux()["reload_needed"] is False
    assert fresh.plan()["steps"] == []
    assert not any(word in {"kill", "kill-server", "kill-session", "kill-pane", "pkill", "rebase", "pull"} for a in calls for word in a)

    # A selected profile that would overwrite runtime settings is blocked.
    bad = new / "home-files/.codex/hooks.json"
    bad.parent.mkdir()
    bad.write_text("{}"); before = snapshot(base)
    try:
        fresh.plan()
        raise AssertionError("mutable link declaration was accepted")
    except control.SafeError as error:
        assert "manages-mutable-agent-files" in str(error)
    assert snapshot(base) == before
print("source/generation/runtime drift, sanitized merge plans, safe dry-run and reconcile apply fixtures passed")
