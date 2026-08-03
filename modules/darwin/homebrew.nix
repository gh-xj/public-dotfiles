{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.darwin;
  supportsMacOSAtLeast = major: cfg.macosMajor == null || cfg.macosMajor >= major;
in
{
  config = lib.mkIf cfg.enable {
    homebrew = {
      enable = lib.mkDefault true;
      user = lib.mkDefault config.system.primaryUser;

      taps = lib.optionals (supportsMacOSAtLeast 15) [
        "typewhisper/tap"
      ];

      brews = [
        "displayplacer"
        "mole"
        "pngpaste"
      ];

      casks = [
        "font-symbols-only-nerd-font"
        "font-recursive-code"
        "ghostty"
        "google-chrome"
        "karabiner-elements"
        "amethyst"
        "insta360-studio"
        "raycast"
        "codex-app"
        "setapp"
        "mimestream"
        "1password"
        "1password-cli"
        "cleanshot"
        "tailscale-app"
      ]
      ++ lib.optionals (supportsMacOSAtLeast 14) [
        "orbstack"
        "chatgpt"
      ]
      ++ lib.optionals (supportsMacOSAtLeast 15) [
        "typewhisper"
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
