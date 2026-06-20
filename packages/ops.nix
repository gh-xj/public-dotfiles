pkgs: [
  pkgs.claude-code
  pkgs.codex
  pkgs.gh
  pkgs.gitleaks
  (pkgs.callPackage ./work-cli.nix { })
]
