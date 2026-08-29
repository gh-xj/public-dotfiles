{ config, lib, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.hooks;
  inherit (publicDotfilesDelivery) mkImmutableFile mkRepoFile mkRepoTree;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      # Live-edited by the operator and by Claude's update-config skill, so
      # these must stay writable; a store link would make every hook tweak
      # require a switch and would break settings.json writes outright.
      ".claude/hooks" = mkRepoTree ".claude/hooks";
      ".claude/settings.json" = mkRepoFile ".claude/settings.json";
      ".claude/statusline-command.sh" = mkImmutableFile ".claude/statusline-command.sh";
      # Same class: repo-backed and live-editable. The repo file already
      # carries its executable bit, so the symlink needs no override.
      ".codex/herdr-agent-state.sh" = mkRepoFile "config/codex/herdr-agent-state.sh";
    };
  };
}
