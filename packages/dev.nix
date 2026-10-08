pkgs: [
  pkgs."bash-language-server"
  pkgs.cloc
  pkgs.d2
  pkgs.delta
  pkgs.difftastic
  pkgs."git-crypt"
  pkgs."git-filter-repo"
  pkgs."go-task"
  pkgs.gofumpt
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
