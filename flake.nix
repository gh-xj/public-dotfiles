{
  description = "xj's public dotfiles baseline";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
  let
    systems = [ "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    allowedUnfreePackages = [
      "claude-code"
    ];
    pkgsFor = system: import nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg:
        builtins.elem (nixpkgs.lib.getName pkg) allowedUnfreePackages;
    };
  in
  {
    homeModules.default = import ./modules/home;
    homeModule = self.homeModules.default;

    darwinModules.default = import ./modules/darwin;
    darwinModule = self.darwinModules.default;

    packageSets = import ./packages;
    lib.packageSets = self.packageSets;

    packages = forAllSystems (system:
      let
        pkgs = pkgsFor system;
      in
      {
        shellTools = pkgs.buildEnv {
          name = "xj-public-shell-tools";
          paths = self.packageSets.shell pkgs;
        };
      });

    homeConfigurations.example = home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor "aarch64-darwin";
      extraSpecialArgs = { inherit inputs self; };
      modules = [
        self.homeModules.default
        ./hosts/example.nix
      ];
    };

    checks = forAllSystems (_system: {
      example-home = self.homeConfigurations.example.activationPackage;
    });
  };
}
