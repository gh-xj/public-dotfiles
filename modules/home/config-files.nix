{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  config = lib.mkIf cfg.enable {
    home.file.".tmux.conf".source = ../../.tmux.conf;

    xdg.configFile = {
      "bat".source = ../../.config/bat;
      "lazydocker".source = ../../.config/lazydocker;
      "lazygit".source = ../../.config/lazygit;
      "starship.toml".source = ../../.config/starship.toml;
      "yazi".source = ../../.config/yazi;
    };
  };
}
