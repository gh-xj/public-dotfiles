pkgs: [
  pkgs.claude-code
  pkgs.gh
  pkgs.gitleaks
  (pkgs.callPackage ./work-cli.nix { })
]
