{
  description = "Synthetic downstream composition example; replace only host data privately";
  inputs = {
    public.url = "github:gh-xj/public-dotfiles";
    nixpkgs.follows = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
  };
  outputs = { public, nixpkgs, home-manager, ... }:
    let
      make = system: extra: home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [ public.homeModules.default ./host.nix ] ++ extra;
      };
      disabled = { xj.publicDotfiles.tmuxRecovery.enable = false; };
    in {
      homeConfigurations.example = make "aarch64-darwin" [ ];
      homeConfigurations.example-x86_64 = make "x86_64-darwin" [ ];
      homeConfigurations.disabled = make "aarch64-darwin" [ disabled ];
      homeConfigurations.disabled-x86_64 = make "x86_64-darwin" [ disabled ];
    };
}
