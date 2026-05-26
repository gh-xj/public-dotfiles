{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  imports = [
    ./agents
    ./config-files.nix
    ./packages.nix
    ./terminal.nix
  ];

  options.xj.publicDotfiles.enable = lib.mkEnableOption "xj public dotfiles Home Manager baseline";

  config = lib.mkIf cfg.enable {
    xj.publicDotfiles.agents.enable = lib.mkDefault true;

    home.file.".hushlogin".source = ../../.hushlogin;
  };
}
