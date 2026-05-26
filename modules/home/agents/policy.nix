{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.agents.policy;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/CLAUDE.md".source = ../../../.claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ../../../.claude/CLAUDE.md;
      ".codex/config.toml".source = lib.mkDefault ../../../.codex/config.toml;
      ".codex/rules".source = ../../../.codex/rules;
    };
  };
}
