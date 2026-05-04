# Ensure Ghostty shell integration also loads in shells spawned later by
# multiplexers (e.g. tmux), so command-finish notifications still work.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration" ]]; then
    source "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
fi

# Aliases and basic shell behavior
# (EDITOR/VISUAL are set in .zprofile so they propagate to non-interactive shells)
setup_aliases() {
    # Navigation shortcuts (j/ji provided by zoxide --cmd j)
    alias ..='cd ..'
    alias -- -='cd -'

    # Modern CLI tools
    alias ls='eza --group-directories-first --git --icons'
    alias tree='eza --tree --level=3 --icons'
    alias ld='lazydocker'
    alias lg='lazygit'
    alias s='fastfetch'
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

# FZF preview command (shared by FZF_DEFAULT_OPTS and yazi wrapper)
_FZF_PREVIEW='bash -c '\''if [[ -d {} ]]; then eza --all --color=always --icons=always --group-directories-first --no-quotes --tree --level=2 --long {}; elif [[ -f {} ]]; then eza --all --color=always --icons=always --no-quotes -l {} && echo && bat --style=numbers --color=always {} 2>/dev/null || cat {}; else echo File not found: {}; fi'\'''

# FZF configuration and file navigation
setup_fzf() {
    export FZF_DEFAULT_OPTS="--height 60% --layout reverse --border top --extended --no-sort --preview \"$_FZF_PREVIEW\" --preview-window=\"right:60%:wrap\""

    export FZF_DEFAULT_COMMAND='fd --max-depth 1 --no-ignore --hidden --follow --exclude ".git" --exclude "node_modules"'
    export FZF_CTRL_T_COMMAND='rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*" 2> /dev/null'
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude ".git" --exclude "node_modules"'

    # FZF completion generators
    _fzf_compgen_path() { fd --hidden --follow --exclude ".git" . "$1"; }
    _fzf_compgen_dir() { fd --type d --hidden --follow --exclude ".git" . "$1"; }

    # Carapace completion
    export CARAPACE_BRIDGES='zsh,bash'
    zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
}

# Install and configure Zinit plugin manager
setup_plugins() {
    # Auto-install Zinit if not present
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        print -P "%F{33}Installing Zinit Plugin Manager...%f"
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
            print -P "%F{34}Installation successful.%f" || print -P "%F{160}Clone failed.%f"
    fi

    source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
    autoload -Uz _zinit
    (( ${+_comps} )) && _comps[zinit]=_zinit

    # Configure autosuggestions
    typeset -g ZSH_AUTOSUGGEST_USE_ASYNC=true

    # Configure zsh-vi-mode (cursor vars must be set inside zvm_config so they
    # resolve *after* vi-mode defines $ZVM_CURSOR_* constants)
    export ZVM_CURSOR_STYLE_ENABLED=true
    zvm_config() {
        ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
        ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BEAM
        ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_VISUAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_VISUAL_LINE_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_OPPEND_MODE_CURSOR=$ZVM_CURSOR_BLINKING_UNDERLINE
    }

    # Load essential plugins
    zinit wait'0a' lucid light-mode for \
        atinit"ZVM_INIT_MODE=sourcing" jeffreytse/zsh-vi-mode \
        Aloxaf/fzf-tab \
        atload"_zsh_autosuggest_start" zsh-users/zsh-autosuggestions \
        hlissner/zsh-autopair \
        MichaelAquilina/zsh-you-should-use

    # Load atuin before syntax highlighting to avoid widget conflicts
    zinit wait'0c' lucid light-mode for \
        atinit"export ATUIN_NOBIND='true'" atload"bindkey '^r' atuin-search" atuinsh/atuin

    # Load syntax highlighting last to avoid conflicts
    zinit wait'0d' lucid light-mode for \
        atinit"zicompinit; zicdreplay" zdharma-continuum/fast-syntax-highlighting

    # Load cached Starship prompt silently
    if [[ ! -f ~/.cache/starship-init.zsh ]] || [[ ~/.config/starship.toml -nt ~/.cache/starship-init.zsh ]] || [[ "$(command -v starship)" -nt ~/.cache/starship-init.zsh ]]; then
        mkdir -p ~/.cache
        starship init zsh > ~/.cache/starship-init.zsh 2>/dev/null
    fi
    source ~/.cache/starship-init.zsh 2>/dev/null

    # Reset terminal title to current directory before each prompt.
    _set_terminal_title() {
        [[ -n "$TMUX" ]] && return 0
        print -Pn "\e]2;%~\a"
    }

    _ghostty_tmux_passthrough_osc() {
        [[ -n "$TMUX" && -n "${GHOSTTY_RESOURCES_DIR:-}" ]] || return 0

        local payload="$1"
        if [[ -n "${_ghostty_fd:-}" ]]; then
            builtin print -rnu "$_ghostty_fd" -- $'\ePtmux;\e\e]'"${payload}"$'\a\e\\'
        else
            builtin print -rn -- $'\ePtmux;\e\e]'"${payload}"$'\a\e\\'
        fi
    }

    nt() {
        local min_seconds=5
        local start="${EPOCHSECONDS:-0}"
        local cmd_text="$*"

        "$@"
        local cmd_status=$?
        local elapsed=$(( ${EPOCHSECONDS:-0} - start ))

        if [[ -n "$TMUX" && -n "${GHOSTTY_RESOURCES_DIR:-}" && $elapsed -ge $min_seconds ]]; then
            local summary="${cmd_text//$'\n'/ }"
            summary="${summary//$'\r'/ }"
            summary="${summary//$'\t'/ }"
            summary="${summary//[^[:print:]]/}"
            summary="${summary//\\/\\\\}"
            summary="${summary//;/,}"
            summary="${summary:0:120}"

            local body="done (${elapsed}s)"
            (( cmd_status == 0 )) || body="failed (${elapsed}s, exit ${cmd_status})"
            _ghostty_tmux_passthrough_osc "9;${summary} ${body}"
        fi

        return $cmd_status
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _set_terminal_title
}

# Custom key bindings
# NOTE: This function is called AFTER vi-mode loads (see zvm_after_init_commands below)
# to prevent vi-mode from overriding our custom keybindings
setup_keybindings() {
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

    # Fix cursor shape on startup - set to beam cursor for insert mode
    print -n '\e[5 q'
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

    # Shell startup benchmarks
    alias benchmark_shell="hyperfine --warmup 3 --runs 10 'zsh -i -c exit'"
    alias benchmark_shell_quick="hyperfine 'zsh -i -c exit'"
    alias benchmark_shell_detailed="hyperfine --warmup 5 --runs 20 --show-output 'zsh -i -c exit'"
}

# Main initialization
# (PATH is fully composed in .zprofile; this file only handles interactive concerns)
init() {
    # Homebrew completions must be on fpath before compinit
    if [[ -d "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions" ]]; then
        fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
    fi

    autoload -Uz compinit
    local zcompdump_file="${ZDOTDIR:-$HOME}/.zcompdump"
    local rebuild_compdump=false

    if [[ ! -f "$zcompdump_file" ]]; then
        rebuild_compdump=true
    else
        zmodload zsh/stat 2>/dev/null
        zmodload zsh/datetime 2>/dev/null
        local -a zcompdump_stat
        if zstat -A zcompdump_stat +mtime -- "$zcompdump_file" 2>/dev/null; then
            local now=$EPOCHSECONDS
            (( now - zcompdump_stat[1] > 86400 )) && rebuild_compdump=true
        else
            rebuild_compdump=true
        fi
    fi

    if [[ "$rebuild_compdump" == true ]]; then
        compinit -d "$zcompdump_file"
    else
        compinit -C -d "$zcompdump_file"
    fi

    setup_plugins

    # Defer initialization until after vi-mode loads
    # setup_keybindings MUST run via zvm_after_init_commands (not earlier)
    # because zsh-vi-mode overrides keybindings during its initialization
    zvm_after_init_commands+=(
        'setup_aliases'
        'setup_fzf'
        'setup_keybindings'  # MUST be after vi-mode to prevent override conflicts
        'setup_utils'
    )

    # Defer bun completion until after compinit finishes (PATH set in .zprofile)
    zinit wait'0e' lucid light-mode as'null' for \
        atinit'[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"' zdharma-continuum/null
}

init

# OpenClaw completion
if [[ -r "$HOME/.openclaw/completions/openclaw.zsh" ]]; then
    source "$HOME/.openclaw/completions/openclaw.zsh"
fi

# Initialize zoxide last so it can install its hooks cleanly.
# Keep interactive mode light; the shared FZF preview is too heavy here.
export _ZO_DOCTOR=0
export _ZO_FZF_OPTS='--height 60% --layout reverse --border top --extended --no-sort'
eval "$(zoxide init zsh --cmd j)"


# agents-cli: version switching for AI coding agents
export PATH="/Users/xj/.agents/shims:$PATH"
