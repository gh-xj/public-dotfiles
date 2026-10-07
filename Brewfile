# Public baseline: apps every Mac running this config needs. Each entry names
# its reason; personal accounts, hardware and taps belong in a downstream
# overlay Brewfile (see docs/dotfiles-operations.md).
macos_major = MacOS.version.to_s.split(".").first.to_i

brew "atuin" # needs: .zsh/bootstrap.zsh history
brew "duti" # needs: config/macos/default-openers.duti
brew "pngpaste" # needs: nvim markdown image paste

cask "font-symbols-only-nerd-font" # needs: Ghostty and Zed fonts
cask "font-recursive-code" # needs: Ghostty and Zed fonts
cask "font-monaspace" # needs: Zed buffer font
cask "ghostty" # needs: .config/ghostty
cask "zed" # needs: .config/zed
cask "karabiner-elements" # needs: .config/karabiner
cask "amethyst" # needs: .config/amethyst
cask "raycast" # needs: .config/raycast
cask "typora" # needs: default-openers.duti Markdown handler
cask "orbstack" if macos_major >= 14 # needs: docker on ~/.orbstack/bin
cask "google-chrome" # baseline: browser
cask "1password" # baseline: credentials
cask "1password-cli" # baseline: op for agents and scripts
cask "claude" # baseline: agent app
cask "codex-app" # baseline: agent app
