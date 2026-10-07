{ config, lib, pkgs, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles;
  packageSets = import ../../packages;
  packageSetNames = builtins.attrNames packageSets;
in
{
  options.xj.publicDotfiles.packageSets = lib.mkOption {
    type = lib.types.listOf (lib.types.enum packageSetNames);
    default = [ "shell" "dev" "ops" ];
    example = [ "shell" "dev" ];
    description = ''
      Named public package sets to install. Available sets are exported from
      the flake as packageSets.shell, packageSets.dev, and packageSets.ops.
    '';
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.mise ] ++ lib.concatMap (name: packageSets.${name} pkgs) cfg.packageSets;
    xdg.configFile."mise/config.toml" = publicDotfilesDelivery.mkRepoFile "config/mise/config.toml";
    xdg.configFile."mise/mise.lock" = publicDotfilesDelivery.mkRepoFile "config/mise/mise.lock";
  };
}
