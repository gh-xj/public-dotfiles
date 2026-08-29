pkgs: [
  pkgs.gh
  pkgs.gitleaks
  (pkgs.callPackage ./work-cli.nix { })
]
