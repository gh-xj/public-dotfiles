{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  settings = ../../config/macos/settings.json;
  tool = pkgs.writeShellApplication {
    name = "macos-settings";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../../scripts/macos-settings.py} \
        --data ${lib.escapeShellArg "${cfg.repoRoot}/config/macos/settings.json"} "$@"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ tool ];

    home.activation.macosSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      $DRY_RUN_CMD ${tool}/bin/macos-settings --data ${settings} apply
    '';
  };
}
