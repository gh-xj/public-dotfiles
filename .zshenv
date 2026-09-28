# Ensure user-local tools are available to non-interactive SSH/Codex shells.
export PATH="$HOME/.local/bin:$PATH"

# Optional account/provider environment; never required by the public baseline.
if [[ -r "$HOME/.config/zsh/private.zshenv" ]]; then
    source "$HOME/.config/zsh/private.zshenv"
fi
