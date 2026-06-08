{ config, lib, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.hooks;
  inherit (publicDotfilesDelivery) mkImmutableFile mkImmutableTree;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/hooks" = mkImmutableTree ".claude/hooks";
      ".claude/settings.json" = mkImmutableFile ".claude/settings.json";
      ".claude/statusline-command.sh" = mkImmutableFile ".claude/statusline-command.sh";
    };
  };
}
