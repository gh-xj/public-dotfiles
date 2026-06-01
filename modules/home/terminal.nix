{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  easyjumpTmux = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "easyjump";
    path = "easyjump.tmux";
    rtpFilePath = "easyjump.tmux";
    version = "unstable-2024-06-22";
    src = pkgs.fetchFromGitHub {
      owner = "roy2220";
      repo = "easyjump.tmux";
      rev = "538479e519698ed44f0cb432736b2274ce5a3e6c";
      hash = "sha256-rckm5DICFYkvfIIy8U3XOXDmGssX/r7npl7Pgpx/bdk=";
    };
    postInstall = ''
      substituteInPlace "$target/easyjump.tmux" \
        --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      package = null;
      baseIndex = 1;
      escapeTime = 0;
      historyLimit = 50000;
      keyMode = "vi";
      mouse = true;
      prefix = "C-s";
      terminal = "tmux-256color";
      plugins = [
        pkgs.tmuxPlugins.fzf-tmux-url
        {
          plugin = easyjumpTmux;
          extraConfig = ''
            set -g @easyjump-key-binding "J"
          '';
        }
        pkgs.tmuxPlugins.session-wizard
        {
          plugin = pkgs.tmuxPlugins.tmux-fzf;
          extraConfig = ''
            TMUX_FZF_LAUNCH_KEY="F"
          '';
        }
      ];
      extraConfig = builtins.readFile ../../.tmux.conf;
    };

    programs.ghostty = {
      enable = true;
      package = null;
      settings = {
        "font-family" = "RecMonoDuotone Nerd Font";
        "adjust-cell-height" = "20%";
        "confirm-close-surface" = false;
        "macos-option-as-alt" = true;
        theme = "light:Atom One Light,dark:One Dark Two";
        "quick-terminal-animation-duration" = 0;
        command = "${pkgs.tmux}/bin/tmux new-session -A -s main";
        "font-thicken" = true;
        "font-size" = 16;
        keybind = [
          "global:cmd+shift+option+a=toggle_quick_terminal"
          "all:cmd+ctrl+h=text:\\x13{"
          "all:cmd+ctrl+l=text:\\x13}"
          "ctrl+digit_1=text:\\x1ba"
          "ctrl+1=text:\\x1ba"
          "ctrl+digit_2=text:\\x1bb"
          "ctrl+2=text:\\x1bb"
          "ctrl+digit_3=text:\\x1bc"
          "ctrl+3=text:\\x1bc"
          "ctrl+digit_4=text:\\x1be"
          "ctrl+4=text:\\x1be"
          "ctrl+digit_5=text:\\x1bg"
          "ctrl+5=text:\\x1bg"
          "ctrl+digit_6=text:\\x1bi"
          "ctrl+6=text:\\x1bi"
          "ctrl+digit_7=text:\\x1bo"
          "ctrl+7=text:\\x1bo"
          "ctrl+digit_8=text:\\x1bp"
          "ctrl+8=text:\\x1bp"
          "ctrl+digit_9=text:\\x1by"
          "ctrl+9=text:\\x1by"
          "shift+left=text:\\x13p"
          "shift+right=text:\\x13n"
          "ctrl+shift+comma=text:\\x13H"
          "ctrl+shift+period=text:\\x13L"
          "super+t=text:\\x13c"
          "super+w=text:\\x13X"
          "super+d=text:\\x13|"
          "super+shift+d=text:\\x13_"
          "super+shift+enter=text:\\x13z"
          "super+ctrl+equal=text:\\x13E"
          "super+digit_1=text:\\x1b1"
          "super+1=text:\\x1b1"
          "super+digit_2=text:\\x1b2"
          "super+2=text:\\x1b2"
          "super+digit_3=text:\\x1b3"
          "super+3=text:\\x1b3"
          "super+digit_4=text:\\x1b4"
          "super+4=text:\\x1b4"
          "super+digit_5=text:\\x1b5"
          "super+5=text:\\x1b5"
          "super+digit_6=text:\\x1b6"
          "super+6=text:\\x1b6"
          "super+digit_7=text:\\x1b7"
          "super+7=text:\\x1b7"
          "super+digit_8=text:\\x1b8"
          "super+8=text:\\x1b8"
          "super+digit_9=text:\\x1b0"
          "super+9=text:\\x1b0"
          "all:super+shift+[=text:\\x13h"
          "all:super+shift+j=text:\\x13j"
          "all:super+shift+k=text:\\x13k"
          "all:super+shift+]=text:\\x13l"
          "shift+enter=text:\\x1b\\r"
        ];
      };
    };
  };
}
