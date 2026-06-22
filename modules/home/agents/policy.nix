{ config, lib, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.policy;
  inherit (publicDotfilesDelivery)
    mkImmutableFile
    mkImmutableTree
    mkMutableSeedActivation
    ;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      "AGENTS.md" = mkImmutableFile ".claude/CLAUDE.md";
      ".claude/CLAUDE.md" = mkImmutableFile ".claude/CLAUDE.md";
      ".codex/AGENTS.md" = mkImmutableFile ".claude/CLAUDE.md";
      ".codex/rules" = mkImmutableTree ".codex/rules";
    };

    home.activation.seedCodexConfig = mkMutableSeedActivation {
      target = "${config.home.homeDirectory}/.codex/config.toml";
      targetDir = "${config.home.homeDirectory}/.codex";
      sourceRel = "config/codex/config.toml";
      legacyStorePatterns = [
        "/nix/store/*/.codex/config.toml"
        "/nix/store/*/config/codex/config.toml"
      ];
      nonWritableMessage = "warning: ${config.home.homeDirectory}/.codex/config.toml is not writable; Codex project trust prompts may fail";
    };
  };
}
