# Aliases and basic shell behavior
# (EDITOR/VISUAL are set in .zprofile so they propagate to non-interactive shells)
setup_aliases() {
    # Navigation shortcuts (j/ji provided by zoxide --cmd j)
    alias ..='cd ..'
    alias -- -='cd -'

    # Modern CLI tools
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
}

setup_aliases
