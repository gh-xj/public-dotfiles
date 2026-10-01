{ config, lib, pkgs, ... }:

let cfg = config.xj.publicDotfiles;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.duti ];
    xdg.configFile."public-dotfiles/default-openers.duti".source = ../../config/macos/default-openers.duti;
  };
}
