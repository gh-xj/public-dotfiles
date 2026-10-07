{ config, lib, pkgs, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles.agents.policy;
  inherit (publicDotfilesDelivery)
    mkRepoFile
    mkRepoTree
    mkMutableSeedActivation
    ;
  policy = { source = pkgs.writeText "global-agent-policy.md" (builtins.readFile ../../../config/agents/policy.md + "\n" + cfg.extraText); };
  rules = { source = pkgs.writeTextDir "default.rules" (builtins.readFile ../../../.codex/rules/default.rules + "\n" + config.xj.publicDotfiles.agents.codexRules.extraText); force = true; };
  policyFile = if cfg.extraText == "" then mkRepoFile "config/agents/policy.md" else policy;
  rulesTree = if config.xj.publicDotfiles.agents.codexRules.extraText == "" then mkRepoTree ".codex/rules" else rules;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      "AGENTS.md" = policyFile;
      ".claude/CLAUDE.md" = policyFile;
      ".codex/AGENTS.md" = policyFile;
      ".codex/rules" = rulesTree;
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
