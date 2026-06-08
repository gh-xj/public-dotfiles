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
    if (( $+widgets[atuin-search] )); then
        bindkey '^r' atuin-search
        bindkey -M emacs '^r' atuin-search 2>/dev/null || true
        bindkey -M viins '^r' atuin-search 2>/dev/null || true
        bindkey -M vicmd '^r' atuin-search 2>/dev/null || true
    fi
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

    setup_fzf
    setup_atuin

    # fzf-tab must load after compinit and before plugins that wrap widgets.
    _source_zsh_file "${XJ_ZSH_FZF_TAB_PLUGIN:-}" || _source_zsh_plugin \
        "fzf-tab/fzf-tab.plugin.zsh" \
        "Aloxaf---fzf-tab/fzf-tab.plugin.zsh"

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
