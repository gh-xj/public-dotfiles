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

setup_aliases

if [[ "${ZSH_MINIMAL:-0}" == 1 ]]; then
    return 0
fi

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

_load_zsh_plugin_paths() {
    local plugin_paths_file="${XJ_ZSH_PLUGIN_PATHS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/xj/zsh/plugin-paths.zsh}"
    [[ -r "$plugin_paths_file" ]] && source "$plugin_paths_file"
}

_source_zsh_file() {
    local file

    for file in "$@"; do
        [[ -n "$file" && -r "$file" ]] || continue
        source "$file"
        return 0
    done

    return 1
}

_source_zsh_plugin() {
    local root rel
    local -a roots

    [[ -n "${XJ_ZSH_PLUGIN_ROOTS:-}" ]] && roots+=(${(s.:.)XJ_ZSH_PLUGIN_ROOTS})
    roots+=(
        "$HOME/.nix-profile/share"
        "/run/current-system/sw/share"
        "/nix/var/nix/profiles/default/share"
    )
    [[ -n "${HOMEBREW_PREFIX:-}" ]] && roots+=("$HOMEBREW_PREFIX/share")
    roots+=("/opt/homebrew/share" "/usr/local/share")
    if [[ "${XJ_ZSH_DISABLE_LEGACY_PLUGIN_CACHE:-0}" != 1 ]]; then
        # Transitional direct-source fallback for pre-Nix local plugin caches.
        roots+=("$HOME/.local/share/zinit/plugins")
    fi
    typeset -U roots

    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        for rel in "$@"; do
            if [[ -r "$root/$rel" ]]; then
                source "$root/$rel"
                return 0
            fi
        done
    done

    return 1
}

setup_atuin() {
    local atuin_bin="${commands[atuin]:-}"
    [[ -n "$atuin_bin" ]] || return 0

    local atuin_cache="$HOME/.cache/atuin-init.zsh"
    if [[ ! -f "$atuin_cache" || "$atuin_bin" -nt "$atuin_cache" ]]; then
        mkdir -p "$HOME/.cache"
        ATUIN_NOBIND=true "$atuin_bin" init zsh >| "$atuin_cache" 2>/dev/null || return 0
    fi

    [[ -r "$atuin_cache" ]] && source "$atuin_cache" 2>/dev/null
    (( $+widgets[atuin-search] )) && bindkey '^r' atuin-search
}

setup_plugins() {
    typeset -g _XJ_KEYBINDINGS_READY=0
    typeset -g ZSH_AUTOSUGGEST_USE_ASYNC=true
    export ZVM_CURSOR_STYLE_ENABLED=true
    export ZVM_INIT_MODE=sourcing

    typeset -ga zvm_after_init_commands
    if (( ${zvm_after_init_commands[(Ie)setup_keybindings]} == 0 )); then
        zvm_after_init_commands+=('setup_keybindings')
    fi

    # Cursor vars must be set inside zvm_config so they resolve after
    # zsh-vi-mode defines $ZVM_CURSOR_* constants.
    zvm_config() {
        ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
        ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BEAM
        ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_VISUAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_VISUAL_LINE_MODE_CURSOR=$ZVM_CURSOR_BLOCK
        ZVM_OPPEND_MODE_CURSOR=$ZVM_CURSOR_BLINKING_UNDERLINE
    }

    _load_zsh_plugin_paths

    _source_zsh_file "${XJ_ZSH_VI_MODE_PLUGIN:-}" || _source_zsh_plugin \
        "zsh-vi-mode/zsh-vi-mode.plugin.zsh" \
        "zsh-vi-mode/zsh-vi-mode.zsh" \
        "jeffreytse---zsh-vi-mode/zsh-vi-mode.plugin.zsh" \
        "jeffreytse---zsh-vi-mode/zsh-vi-mode.zsh"

    setup_atuin

    _source_zsh_file "${XJ_ZSH_AUTOSUGGESTIONS_PLUGIN:-}" || _source_zsh_plugin \
        "zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "zsh-autosuggestions/zsh-autosuggestions.zsh"

    _source_zsh_file "${XJ_ZSH_AUTOPAIR_PLUGIN:-}" || _source_zsh_plugin \
        "zsh/zsh-autopair/autopair.zsh"

    # Load syntax highlighting last to avoid widget conflicts.
    _source_zsh_file "${XJ_ZSH_SYNTAX_HIGHLIGHTING_PLUGIN:-}" || _source_zsh_plugin \
        "zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
        "zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

    # Load cached Starship prompt silently
    local starship_cache="$HOME/.cache/starship-init.zsh"
    local starship_bin="${commands[starship]:-}"
    if [[ -n "$starship_bin" && ( ! -f "$starship_cache" || "$HOME/.config/starship.toml" -nt "$starship_cache" || "$starship_bin" -nt "$starship_cache" ) ]]; then
        mkdir -p ~/.cache
        "$starship_bin" init zsh >| "$starship_cache" 2>/dev/null
    fi
    [[ -r "$starship_cache" ]] && source "$starship_cache" 2>/dev/null

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

    # Shell startup benchmarks
    alias benchmark_shell="hyperfine --warmup 3 --runs 10 'zsh -i -c exit'"
    alias benchmark_shell_quick="hyperfine 'zsh -i -c exit'"
    alias benchmark_shell_detailed="hyperfine --warmup 5 --runs 20 --show-output 'zsh -i -c exit'"
}

# Main initialization
# (PATH is fully composed in .zprofile; this file only handles interactive concerns)
init() {
    # Homebrew completions must be on fpath before compinit
    local homebrew_prefix="${HOMEBREW_PREFIX:-}"
    [[ -z "$homebrew_prefix" && -d /opt/homebrew/share/zsh/site-functions ]] && homebrew_prefix="/opt/homebrew"
    [[ -z "$homebrew_prefix" && -d /usr/local/share/zsh/site-functions ]] && homebrew_prefix="/usr/local"
    if [[ -n "$homebrew_prefix" && -d "$homebrew_prefix/share/zsh/site-functions" ]]; then
        fpath=("$homebrew_prefix/share/zsh/site-functions" $fpath)
    fi
    typeset -gU fpath

    autoload -Uz compinit
    local zcompdump_file="${ZDOTDIR:-$HOME}/.zcompdump"
    local zcompdump_zwc="${zcompdump_file}.zwc"
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
        [[ -f "$zcompdump_file" ]] && zcompile "$zcompdump_file" 2>/dev/null || true
    else
        if [[ -f "$zcompdump_file" && ( ! -f "$zcompdump_zwc" || "$zcompdump_file" -nt "$zcompdump_zwc" ) ]]; then
            zcompile "$zcompdump_file" 2>/dev/null || true
        fi
        compinit -C -d "$zcompdump_file"
    fi

    setup_plugins

    setup_fzf
    setup_utils

    if (( ! ${_XJ_KEYBINDINGS_READY:-0} )); then
        setup_keybindings
    fi

    # Source bun completion after compinit finishes (PATH set in .zprofile).
    [[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
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
if (( $+commands[zoxide] )); then
    _zoxide_cache="$HOME/.cache/zoxide-init.zsh"
    _zoxide_bin="$commands[zoxide]"
    if [[ ! -f "$_zoxide_cache" || "$_zoxide_bin" -nt "$_zoxide_cache" ]]; then
        mkdir -p "$HOME/.cache"
        "$_zoxide_bin" init zsh --cmd j >| "$_zoxide_cache" 2>/dev/null
    fi
    [[ -r "$_zoxide_cache" ]] && source "$_zoxide_cache" 2>/dev/null
fi
unset _zoxide_cache _zoxide_bin
