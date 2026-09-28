{ config, lib, pkgs, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.policy;
  inherit (publicDotfilesDelivery)
    mkMutableSeedActivation
    ;
  policy = pkgs.writeText "global-agent-policy.md" (builtins.readFile ../../../.claude/CLAUDE.md + "\n" + cfg.extraText);
  rules = pkgs.writeTextDir "default.rules" (builtins.readFile ../../../.codex/rules/default.rules + "\n" + config.xj.publicDotfiles.agents.codexRules.extraText);
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      "AGENTS.md".source = policy;
      ".claude/CLAUDE.md".source = policy;
      ".codex/AGENTS.md".source = policy;
      ".codex/rules" = { source = rules; force = true; };
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
