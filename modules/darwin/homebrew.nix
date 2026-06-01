{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.darwin;
in
{
  config = lib.mkIf cfg.enable {
    homebrew = {
      enable = lib.mkDefault true;
      user = lib.mkDefault config.system.primaryUser;

      taps = [ ];

      brews = [
        "googleworkspace-cli"
        "markdownlint-cli2"
        "marksman"
        "pngpaste"
      ];

      casks = [
        "font-symbols-only-nerd-font"
        "font-recursive"
        "font-recursive-code"
        "handy"
        "ghostty"
        "arc"
        "google-chrome"
        "karabiner-elements"
        "amethyst"
        "raycast"
        "orbstack"
        "chatgpt"
        "codex-app"
        "1password"
        "1password-cli"
        "cleanshot"
        "tailscale-app"
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
