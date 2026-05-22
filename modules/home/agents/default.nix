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
    hooks.enable = lib.mkEnableOption "public agent hook files";
  };

  config = lib.mkIf cfg.enable {
    xj.publicDotfiles.agents = {
      policy.enable = lib.mkDefault true;
      hooks.enable = lib.mkDefault true;
    };
  };
}
