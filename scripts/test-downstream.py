#!/usr/bin/env python3
"""Build an independent downstream flake against this checkout, never activate it."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parent.parent
generation = Path(sys.argv[1]).resolve()
nix = ["nix", "--extra-experimental-features", "nix-command flakes"]
suffix = "" if platform.machine() == "arm64" else "-x86_64"
with tempfile.TemporaryDirectory(prefix="downstream-composition-") as tmp:
    fixture = Path(tmp) / "flake"
    shutil.copytree(repo / "examples/downstream", fixture)
    common = ["--override-input", "public", "path:" + str(repo), "--no-write-lock-file"]
    def evaluate(profile, expression):
        result = subprocess.check_output([*nix, "eval", "--json", str(fixture) + "#homeConfigurations." + profile,
                                          *common, "--apply", expression], text=True)
        return json.loads(result)
    def build(profile):
        return Path(subprocess.check_output([*nix, "build", "--no-link", "--print-out-paths",
                                            str(fixture) + "#homeConfigurations." + profile + ".activationPackage", *common], text=True).strip())
    built = build("example" + suffix)
    files = (built / "home-files").resolve()
    config = evaluate("example" + suffix, '''h: {
      seed = builtins.hasAttr "seedCodexHooks" h.config.home.activation;
      recovery = builtins.hasAttr ".local/bin/tmux-recovery" h.config.home.file;
      schedule = h.config.launchd.agents.tmux-recovery.config;
      packages = map (p: p.name) h.config.home.packages;
    }''')
    assert config["seed"] is False and config["recovery"] is True
    assert config["schedule"]["ProgramArguments"] == ["/Users/example/.local/bin/tmux-recovery", "checkpoint-all"]
    assert config["schedule"]["StartInterval"] == 300 and config["schedule"]["Umask"] == 63
    assert "scratch-gc" not in config["packages"]
    policy_paths = [files / p for p in ("AGENTS.md", ".claude/CLAUDE.md", ".codex/AGENTS.md")]
    assert len({p.resolve() for p in policy_paths}) == 1
    assert "Downstream fixture policy" in policy_paths[0].read_text()
    assert "fixture-only-command" in (files / ".codex/rules/default.rules").read_text()
    rule = json.loads(subprocess.check_output(["codex", "execpolicy", "check", "--rules", str(files / ".codex/rules/default.rules"), "--", "fixture-only-command"], text=True))
    assert rule["decision"] == "prompt"
    assert "downstream-hook-fixture" in (files / ".codex/hooks.json").read_text()
    assert "downstream-scratch-fixture" in (files / ".local/bin/scratch-gc").read_text()
    metadata = json.loads((files / ".config/public-dotfiles/generation.json").read_text())
    assert ".codex/hooks.json" not in metadata["mutable_targets"]
    wrapper = (files / ".local/bin/tmux-recovery").read_text()
    assert "--keep-newest 8" in wrapper and "--keep-days 3" in wrapper and "--adapters" in wrapper
    layout = files / ".config/xj/display-layouts.tsv"
    assert layout.read_text() == (fixture / "display-layouts.tsv").read_text()
    fake_bin = Path(tmp) / "bin"
    fake_bin.mkdir()
    display = fake_bin / "displayplacer"
    display.write_text('#!/bin/sh\nprintf "%s\\n" "Persistent screen id: fixture" "Serial screen id: DISPLAY-FIXTURE" "Resolution: 640x480" "Hertz: 60" "Color Depth: 8" "Scaling: off" "Origin: (0,0)" "Rotation: 0" "Enabled: true"\n')
    display.chmod(0o700)
    preview = subprocess.check_output(["bash", str(repo / "scripts/apply-display-layout.sh"), "--layouts", str(layout), "--dry-run"],
                                      env=dict(os.environ, PATH=str(fake_bin) + ":" + os.environ["PATH"]), text=True)
    assert "800x600" in preview and "DISPLAY-FIXTURE" in preview
    workmux_file = files / ".config/workmux/config.yaml"
    workmux = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", str(workmux_file)], text=True))
    assert workmux["agent"] == "custom" and workmux["status_format"] is False
    assert workmux["agents"]["custom"]["command"] == "custom-cli codex" and workmux["agents"]["custom"]["type"] == "codex"
    native_home = Path(tmp) / "runtime"
    (native_home / ".config/workmux").mkdir(parents=True)
    shutil.copyfile(workmux_file, native_home / ".config/workmux/config.yaml")
    subprocess.run([str(built / "home-path/bin/workmux"), "set-window-status", "working"], cwd=native_home,
                   env={"HOME": str(native_home), "XDG_CONFIG_HOME": str(native_home / ".config"), "PATH": "/usr/bin:/bin"}, check=True, capture_output=True)
    disabled = build("disabled" + suffix)
    off = evaluate("disabled" + suffix, '''h: {
      link = builtins.hasAttr ".local/bin/tmux-recovery" h.config.home.file;
      packages = map (p: p.name) h.config.home.packages;
      job = h.config.launchd.agents.tmux-recovery.enable or false;
    }''')
    assert not off["link"] and "tmux-recovery" not in off["packages"] and not off["job"]
    assert not (disabled / "home-files/.local/bin/tmux-recovery").exists()
    public = (generation / "home-files").resolve()
    assert not (public / ".local/bin/scratch-gc").exists()
    assert not (public / ".config/xj/display-layouts.tsv").exists()
    assert "Downstream fixture policy" not in (public / "AGENTS.md").read_text()
    assert not list((public / "Library/LaunchAgents").glob("*tmux-recovery*")) if (public / "Library/LaunchAgents").exists() else True
    print("standalone/downstream builds, ownership switches, policy/rules, Workmux argv, display data and recovery schedule verified")
