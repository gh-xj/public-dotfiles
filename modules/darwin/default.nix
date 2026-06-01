{ lib, ... }:

{
  imports = [
    ./defaults.nix
    ./homebrew.nix
  ];

  options.xj.publicDotfiles.darwin.enable = lib.mkEnableOption "xj public dotfiles nix-darwin baseline";

  config = { };
}
