{ lib, ... }:

{
  options.xj.publicDotfiles.darwin.enable = lib.mkEnableOption "xj public dotfiles nix-darwin baseline";

  config = { };
}
