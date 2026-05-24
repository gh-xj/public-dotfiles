{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.darwin;
in
{
  config = lib.mkIf cfg.enable {
    homebrew = {
      enable = lib.mkDefault true;
      user = lib.mkDefault config.system.primaryUser;

      brews = [
        "googleworkspace-cli"
        "hl"
        "markdownlint-cli2"
        "marksman"
        "pngpaste"
      ];

      casks = [
        "gcloud-cli"
        "handy"
      ];

      onActivation = {
        autoUpdate = lib.mkDefault false;
        upgrade = lib.mkDefault false;
        cleanup = lib.mkDefault "none";
        extraEnv.HOMEBREW_NO_ENV_HINTS = "1";
      };
    };
  };
}
