{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  imports = [
    ./agents
    ./delivery.nix
    ./config-files.nix
    ./packages.nix
    ./shell.nix
    ./terminal.nix
  ];

  options.xj.publicDotfiles = {
    enable = lib.mkEnableOption "xj public dotfiles Home Manager baseline";
    repoRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/public-dotfiles";
      description = "Absolute path to the checked-out public-dotfiles repository for direct live config symlinks.";
    };
  };

  config = lib.mkIf cfg.enable {
    xj.publicDotfiles.agents.enable = lib.mkDefault true;

    home.file.".hushlogin".source = ../../.hushlogin;
  };
}
