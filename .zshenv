# Login and non-login shells share one explicit provider order.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export PATH="$HOME/.local/bin:$XDG_DATA_HOME/mise/shims:$XDG_STATE_HOME/nix/profiles/home-manager/home-path/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
typeset -gU path

# Optional account/provider environment; never required by the public baseline.
if [[ -r "$HOME/.config/zsh/private.zshenv" ]]; then
    source "$HOME/.config/zsh/private.zshenv"
fi
