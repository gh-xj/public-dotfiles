{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  policy = ../../config/macos/default-openers.duti;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.duti ];
    xdg.configFile."public-dotfiles/default-openers.duti".source = policy;
    home.activation.defaultOpeners = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD ${pkgs.duti}/bin/duti ${policy}
    '';
  };
}
