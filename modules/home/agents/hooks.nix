{ config, lib, pkgs, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.hooks;
  inherit (publicDotfilesDelivery) mkImmutableFile mkMutableSeedActivation;
  status = pkgs.writeShellApplication {
    name = "agent-workmux-status";
    runtimeInputs = [ (pkgs.callPackage ../../../packages/workmux.nix { }) ];
    text = builtins.readFile ../../../scripts/agent-workmux-status.sh;
  };
  paneTitle = pkgs.writeShellApplication {
    name = "agent-pane-title";
    runtimeInputs = [ pkgs.python3 pkgs.tmux ];
    text = ''exec python3 ${../../../scripts/agent-pane-title.py} "$@"'';
  };
  session = pkgs.writeShellApplication {
    name = "agent-session";
    runtimeInputs = [ pkgs.python3 pkgs.tmux pkgs.git paneTitle ];
    text = ''exec python3 ${../../../scripts/agent-session.py} "$@"'';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/statusline-command.sh" = mkImmutableFile ".claude/statusline-command.sh";
      ".local/bin/agent-pane-title".source = "${paneTitle}/bin/agent-pane-title";
      ".local/bin/agent-session".source = "${session}/bin/agent-session";
      ".local/bin/agent-workmux-status".source = "${status}/bin/agent-workmux-status";
    };
    home.packages = [ paneTitle session status ];
    home.activation.seedCodexHooks = lib.mkIf config.xj.publicDotfiles.agents.codexHooks.seed.enable (mkMutableSeedActivation {
      target = "${config.home.homeDirectory}/.codex/hooks.json";
      targetDir = "${config.home.homeDirectory}/.codex";
      sourceRel = "config/codex/hooks.json";
      legacyStorePatterns = [ "/nix/store/*" "${config.xj.publicDotfiles.repoRoot}/config/codex/hooks.json" ];
    });
    home.activation.seedClaudeSettings = mkMutableSeedActivation {
      target = "${config.home.homeDirectory}/.claude/settings.json";
      targetDir = "${config.home.homeDirectory}/.claude";
      sourceRel = "config/claude/settings.json";
      legacyStorePatterns = [
        "/nix/store/*"
        "${config.xj.publicDotfiles.repoRoot}/.claude/settings.json"
        "${config.xj.publicDotfiles.repoRoot}/config/claude/settings.json"
      ];
    };
  };
}
