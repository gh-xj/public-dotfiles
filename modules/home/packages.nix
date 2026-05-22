{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  packageSets = import ../../packages;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = lib.concatLists [
      (packageSets.dev pkgs)
      (packageSets.ops pkgs)
      (packageSets.teaching pkgs)
    ];
  };
}
