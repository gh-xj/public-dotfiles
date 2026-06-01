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
        "homebrew/autoupdate"
        "daipeihust/tap"
        "typewhisper/tap"
      ];

      brews = [
        "nvm"
        "bluetoothconnector"
        "cliclick"
        "daipeihust/tap/im-select"
        "googleworkspace-cli"
        "hl"
        "markdownlint-cli2"
        "marksman"
        "pngpaste"
        "watchman"
      ];

      casks = [
        "font-fira-code-nerd-font"
        "font-hack-nerd-font"
        "font-symbols-only-nerd-font"
        "font-recursive"
        "font-recursive-code"
        "font-pt-mono"
        "gcloud-cli"
        "handy"
        "ghostty"
        "arc"
        "google-chrome"
        "firefox"
        "karabiner-elements"
        "amethyst"
        "raycast"
        "dropbox"
        "feishu"
        "lark"
        "slack"
        "slack-cli"
        "zoom"
        "discord"
        "timing"
        "fantastical"
        "mimestream"
        "obsidian"
        "telegram"
        "wechat"
        "wetype"
        "orbstack"
        "bruno"
        "ngrok"
        "github"
        "chatgpt"
        "codex-app"
        "copilot-money"
        "superwhisper"
        "typewhisper"
        "bitwarden"
        "1password"
        "1password-cli"
        "little-snitch"
        "calibre"
        "cleanshot"
        "tailscale-app"
        "tencent-lemon"
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
