{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  packageSets = import ../../packages;
  packageSetNames = builtins.attrNames packageSets;
in
{
  options.xj.publicDotfiles.packageSets = lib.mkOption {
    type = lib.types.listOf (lib.types.enum packageSetNames);
    default = [ "dev" "ops" "teaching" ];
    example = [ "dev" "teaching" ];
    description = ''
      Named public package sets to install. Available sets are exported from
      the flake as packageSets.dev, packageSets.ops, and packageSets.teaching.
    '';
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.concatMap (name: packageSets.${name} pkgs) cfg.packageSets;
  };
}
