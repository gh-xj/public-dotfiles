pkgs: [
  pkgs."bash-language-server"
  pkgs.delta
  pkgs.difftastic
  pkgs."git-crypt"
  pkgs."git-filter-repo"
  pkgs."go-task"
  pkgs.gopls
  pkgs.lazygit
  pkgs.marksman
  pkgs.neovim
  pkgs.pyright
  pkgs.shfmt
  pkgs.tmux
  pkgs.typescript
  pkgs."typescript-language-server"
  pkgs."vscode-langservers-extracted"
  (pkgs.callPackage ./workmux.nix { })
]
