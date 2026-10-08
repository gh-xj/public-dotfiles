{ config, pkgs, ... }:
{
  home = { username = "example"; homeDirectory = "/Users/example"; stateVersion = "25.11"; };
  programs.home-manager.enable = true;
  xj.publicDotfiles = {
    enable = true;
    repoRoot = "${config.home.homeDirectory}/public-dotfiles";
    agents.policy.extraText = "Downstream fixture policy: keep host-only requirements here.";
    agents.codexRules.extraText = ''prefix_rule(pattern=["fixture-only-command"], decision="prompt")'';
    agents.codexHooks.seed.enable = false;
    agents.hooks.enable = true;
    agents.claudeSettings.seed.enable = false;
    workmux = {
      agent = "custom";
      extraAgents.custom = { argv = [ "custom-cli" "codex" ]; type = "codex"; };
    };
    tmuxRecovery = {
      enable = true;
      schedule.enable = true;
      schedule.interval = 300;
      keepNewest = 8;
      keepDays = 3;
      adaptersFile = "${config.home.homeDirectory}/.config/tmux-recovery/adapters.json";
    };
    scratchGc.enable = false;
    retention = { enable = true; logs.maxMegabytes = 20; scratch.fixture = { root = "${config.home.homeDirectory}/scratch"; maxAgeDays = 7; }; };
    encryptedMirrors.fixture = { repository = "${config.home.homeDirectory}/overlay"; remote = "/srv/fixture-mirror"; gpgKey = "FIXTUREKEYID"; };
  };
  # These synthetic private-owner declarations prove there is no public target
  # conflict. A real owner should preserve mutable hook edits with its own seed
  # workflow; this fixture is not an account/runtime configuration template.
  home.file.".codex/hooks.json".source = ./hooks.json;
  home.file.".claude/settings.json".text = builtins.toJSON { downstream_settings_fixture = true; };
  home.file.".local/bin/scratch-gc".source = "${pkgs.writeShellScriptBin "fixture-scratch-gc" "echo downstream-scratch-fixture"}/bin/fixture-scratch-gc";
  home.file.".config/tmux-recovery/adapters.json".source = ./adapters.json;
}
