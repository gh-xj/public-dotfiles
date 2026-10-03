pkgs: [
  pkgs.delta
  pkgs.difftastic
  pkgs."go-task"
  pkgs.lazygit
  pkgs.marksman
  pkgs.neovim
  pkgs.shfmt
  pkgs.tmux
  (pkgs.callPackage ./workmux.nix { })
]
