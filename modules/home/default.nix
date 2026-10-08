{ config, lib, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles;
in
{
  imports = [
    ./agents
    ./delivery.nix
    ./config-files.nix
    ./default-openers.nix
    ./macos-settings.nix
    ./packages.nix
    ./shell.nix
    ./terminal.nix
    ./control.nix
    ./recovery.nix
    ./retention.nix
    ./backup.nix
    ./composition.nix
  ];

  options.xj.publicDotfiles = {
    enable = lib.mkEnableOption "xj public dotfiles Home Manager baseline";
    repoRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/public-dotfiles";
      description = "Absolute path to the checked-out public-dotfiles repository for direct live config symlinks.";
    };
    operationsTaskfile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.repoRoot}/Taskfile.yml";
      description = "Absolute Taskfile path for the host's dotfiles owner, exposed by task -g dotfiles:COMMAND.";
    };
    zshEnvExtra = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Optional downstream Home Manager overlay loaded by the live .zshenv.";
    };
  };

  config = lib.mkIf cfg.enable {
    xj.publicDotfiles.agents.enable = lib.mkDefault true;

    home.file.".hushlogin" = publicDotfilesDelivery.mkRepoFile ".hushlogin";
  };
}
