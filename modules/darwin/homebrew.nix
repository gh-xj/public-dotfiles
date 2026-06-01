{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.darwin;
in
{
  config = lib.mkIf cfg.enable {
    homebrew = {
      enable = lib.mkDefault true;
      user = lib.mkDefault config.system.primaryUser;

      taps = [
        "typewhisper/tap"
      ];

      brews = [
        "displayplacer"
        "gemini-cli"
        "googleworkspace-cli"
        "markdownlint-cli2"
        "marksman"
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
        "raycast"
        "orbstack"
        "chatgpt"
        "codex-app"
        "setapp"
        "typewhisper"
        "mimestream"
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
