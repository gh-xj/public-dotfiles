{ lib, ... }:

{
  imports = [
    ./defaults.nix
    ./homebrew.nix
  ];

  options.xj.publicDotfiles.darwin = {
    enable = lib.mkEnableOption "xj public dotfiles nix-darwin baseline";

    macosMajor = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Detected macOS major version used to gate Homebrew casks that require newer macOS releases.";
    };
  };

  config = { };
}
