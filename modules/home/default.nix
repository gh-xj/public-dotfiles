{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  imports = [
    ./terminal.nix
  ];

  options.xj.publicDotfiles.enable = lib.mkEnableOption "xj public dotfiles Home Manager baseline";

  config = lib.mkIf cfg.enable {
    home.file.".hushlogin".source = ../../.hushlogin;
  };
}
