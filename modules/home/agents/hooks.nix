{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.agents.hooks;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/hooks".source = ../../../.claude/hooks;
      ".claude/settings.json".source = ../../../.claude/settings.json;
      ".claude/statusline-command.sh".source = ../../../.claude/statusline-command.sh;
    };
  };
}
