{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  config = lib.mkIf cfg.enable {
    home.file.".tmux.conf".source = ../../.tmux.conf;

    xdg.configFile = {
      "bat" = {
        source = ../../.config/bat;
        force = true;
      };
      "lazydocker" = {
        source = ../../.config/lazydocker;
        force = true;
      };
      "lazygit" = {
        source = ../../.config/lazygit;
        force = true;
      };
      "starship.toml".source = ../../.config/starship.toml;
      "yazi" = {
        source = ../../.config/yazi;
        force = true;
      };
    };
  };
}
