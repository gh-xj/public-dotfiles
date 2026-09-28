{ config, lib, pkgs, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.hooks;
  inherit (publicDotfilesDelivery) mkImmutableFile mkMutableSeedActivation;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/statusline-command.sh" = mkImmutableFile ".claude/statusline-command.sh";
    };
    home.packages = map (name: pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.python3 pkgs.tmux pkgs.git ];
      text = ''exec python3 ${../../../scripts + "/${name}.py"} "$@"'';
    }) [ "agent-pane-title" "agent-session" ];
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
