{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.agents;
in
{
  imports = [
    ./hooks.nix
    ./policy.nix
  ];

  options.xj.publicDotfiles.agents = {
    enable = lib.mkEnableOption "xj public agent configuration baseline";

    policy.enable = lib.mkEnableOption "public agent policy files";
    policy.extraText = lib.mkOption { type = lib.types.lines; default = ""; description = "Downstream-only policy appended to the shared Claude/Codex global policy."; };
    codexHooks.seed.enable = lib.mkOption { type = lib.types.bool; default = true; description = "Seed and migrate public Codex hooks. Disable when a downstream private owner manages this runtime file."; };
    codexRules.extraText = lib.mkOption { type = lib.types.lines; default = ""; description = "Downstream-only Codex rules appended after generic public rules."; };
    hooks.enable = lib.mkEnableOption "public agent hook files";
  };

  config = lib.mkIf cfg.enable {
    xj.publicDotfiles.agents = {
      policy.enable = lib.mkDefault true;
      hooks.enable = lib.mkDefault true;
    };
  };
}
