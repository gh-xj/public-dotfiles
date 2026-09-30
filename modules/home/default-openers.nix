{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  policy = ../../config/macos/default-openers.duti;
  openers = pkgs.writeShellApplication {
    name = "default-openers";
    runtimeInputs = [ pkgs.python3 pkgs.duti ];
    text = ''exec python3 ${../../scripts/default-openers.py} --policy ${policy} "$@"'';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ openers pkgs.duti ];
    home.file.".local/bin/default-openers".source = "${openers}/bin/default-openers";
    xdg.configFile."public-dotfiles/default-openers.duti".source = policy;
    # Home Manager runs before the Homebrew app install on a fresh bootstrap.
    # Missing apps are reported here; the Darwin bootstrap reapplies strictly.
    home.activation.defaultOpeners = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD ${openers}/bin/default-openers apply --skip-missing
    '';
  };
}
