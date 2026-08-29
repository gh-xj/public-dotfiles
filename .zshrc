typeset -g _XJ_ZSHRC_FILE="${${(%):-%x}:A}"
typeset -g _XJ_ZSH_MODULE_DIR="${_XJ_ZSHRC_FILE:h}/.zsh"

# Ghostty shell integration also loads in nested shells (tmux, etc.) so
# command-finish notifications still work.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration" ]]; then
    source "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
fi

# Aliases and the tmux wrapper are always available, including in ZSH_MINIMAL.
alias ..='cd ..'
alias -- -='cd -'
alias ls='eza --group-directories-first --git --icons'
alias tree='eza --tree --level=3 --icons'
alias lg='lazygit'
alias k='kubectl'
alias b='nvim .'

t() {
    if (( $# == 0 )); then
        tmux attach || tmux
    else
        tmux "$@"
    fi
}

if [[ "${ZSH_MINIMAL:-0}" == 1 ]]; then
    unset _XJ_ZSHRC_FILE _XJ_ZSH_MODULE_DIR
    return 0
fi

source "${_XJ_ZSH_MODULE_DIR}/bootstrap.zsh"

unset _XJ_ZSHRC_FILE _XJ_ZSH_MODULE_DIR
