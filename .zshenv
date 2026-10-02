# Ensure user-local tools are available to non-interactive SSH/Codex shells.
typeset -U path  # login shells add some of these again in .zprofile
# The activated Home Manager profile is the authority for declared CLI tools,
# including home-only switches on nix-darwin hosts with useUserPackages.
export PATH="$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/npm-global/bin:${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager/home-path/bin:$PATH"

# Optional account/provider environment; never required by the public baseline.
if [[ -r "$HOME/.config/zsh/private.zshenv" ]]; then
    source "$HOME/.config/zsh/private.zshenv"
fi
