# Custom key bindings
# NOTE: This function is called AFTER vi-mode loads (see zvm_after_init_commands below)
# to prevent vi-mode from overriding our custom keybindings
setup_keybindings() {
    (( ${_XJ_KEYBINDINGS_READY:-0} )) && return 0
    typeset -g _XJ_KEYBINDINGS_READY=1

    # Use forward-char so zsh-autosuggestions accepts the current suggestion.
    bindkey -M emacs '^F' forward-char
    bindkey -M viins '^F' forward-char
    bindkey -M vicmd '^F' vi-forward-char

    run_yazi_widget() {
        BUFFER="y"
        zle accept-line
    }
    zle -N run_yazi_widget
    bindkey '^y' run_yazi_widget

    # Lazygit widget
    run_lazygit_widget() {
        BUFFER="lazygit"
        zle accept-line
    }

    zle -N run_lazygit_widget
    bindkey '^g' run_lazygit_widget

    # Fix cursor shape on startup - set to beam cursor for insert mode.
    [[ -t 1 ]] && print -n '\e[5 q'
}

# Utility functions and tools
setup_utils() {
    # Yazi wrapper: on exit, cd into the directory yazi was browsing.
    y() {
        local FZF_DEFAULT_OPTS="--extended --no-sort --reverse --preview \"$_FZF_PREVIEW\" --preview-window=\"right:60%:wrap\""
        local tmp cwd
        tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        IFS= read -r -d '' cwd < "$tmp"
        [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
        rm -f -- "$tmp"
    }
}
