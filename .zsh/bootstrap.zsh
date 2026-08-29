# Consolidated interactive-shell bootstrap.
# Merged from the retired numbered files:
#   20-completion.zsh  → FZF, SSH host completion
#   30-plugins.zsh     → vi-mode, atuin, fzf-tab, autosuggestions, syntax-hi,
#                        starship, terminal title, ghostty nt() wrapper
#   40-interactive.zsh → keybindings, yazi wrapper
#   50-init.zsh        → compinit orchestrator (init) and its invocation
#   60-post-init.zsh   → OpenClaw completion, zoxide (loaded after init())
#
# Loading order is preserved so vi-mode still initializes before
# setup_keybindings runs (via zvm_after_init_commands).

#
# --- Completion helpers (was 20-completion.zsh) ---
#
# Source a tool's shell-init output from ~/.cache, regenerating the cache when
# the tool's binary -- or any extra dependency path given before "--" -- is
# newer than it. Returns non-zero when the tool is absent or generation failed,
# so callers can skip their follow-up wiring.
#
#   _xj_cache_tool_init <name> [extra-dep-path...] -- <command...>
_xj_cache_tool_init() {
    # Deliberately no `emulate -L zsh` here. The -L flag implies LOCAL_OPTIONS,
    # which reverts every `setopt` the sourced init performs as soon as this
    # function returns -- silently killing starship's `setopt promptsubst` (the
    # prompt then renders its own $(...) literally) and atuin's
    # `setopt interactive_comments`. Do not add it back.

    local name="$1"; shift
    local -a deps=()
    while (( $# )) && [[ "$1" != "--" ]]; do
        deps+=("$1")
        shift
    done
    shift  # drop the "--" separator

    local bin="${commands[$name]:-}"
    [[ -n "$bin" ]] || return 1

    local cache="$HOME/.cache/${name}-init.zsh"
    local dep
    integer stale=0

    [[ -f "$cache" ]] || stale=1
    [[ "$bin" -nt "$cache" ]] && stale=1
    for dep in "${deps[@]}"; do
        [[ -e "$dep" && "$dep" -nt "$cache" ]] && stale=1
    done

    if (( stale )); then
        mkdir -p "$HOME/.cache"
        "$@" >| "$cache" 2>/dev/null || return 1
    fi

    [[ -r "$cache" ]] || return 1
    source "$cache" 2>/dev/null
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

    _xj_cache_tool_init fzf -- fzf --zsh

    zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
    zstyle -e ':completion:*:(ssh|scp|sftp|ssh-copy-id|rsync):*:hosts' hosts '_xj_ssh_completion_hosts_style'
}

_xj_should_complete_literal_ssh_host() {
    emulate -L zsh

    local host="$1"

    [[ -n "$host" ]] || return 1
    case "$host" in
        (\!*|\|*|*[\*\?\[\]]*)
            return 1
            ;;
    esac

    return 0
}

_xj_should_complete_default_ssh_host() {
    emulate -L zsh

    local host="$1"

    _xj_should_complete_literal_ssh_host "$host" || return 1
    [[ "$host" == _* ]] && return 1
    return 0
}

_xj_collect_ssh_config_hosts_from_file() {
    emulate -L zsh

    local file="$1"
    local resolved key rest token include_pattern raw_line
    local -a tokens include_matches lines
    integer idx

    [[ -r "$file" ]] || return 0
    resolved="${file:A}"
    [[ -n "${seen_files[$resolved]:-}" ]] && return 0
    seen_files[$resolved]=1

    lines=("${(@f)$(<"$resolved")}")
    idx=1
    while (( idx <= ${#lines} )); do
        raw_line="${lines[idx]%%\#*}"
        IFS=$'=\t ' read -r key rest <<< "$raw_line"

        case "${key:l}" in
            (host)
                tokens=(${(z)rest})
                for token in "${tokens[@]}"; do
                    _xj_should_complete_literal_ssh_host "$token" || continue
                    hosts+=("$token")
                done
                ;;
            (include)
                tokens=(${(z)rest})
                for token in "${tokens[@]}"; do
                    include_pattern="$token"
                    if [[ "$include_pattern" != /* && "$include_pattern" != ~* ]]; then
                        include_pattern="${resolved:h}/$include_pattern"
                    fi
                    include_matches=(${~include_pattern}(N))
                    for file in "${include_matches[@]}"; do
                        _xj_collect_ssh_config_hosts_from_file "$file"
                    done
                done
                ;;
        esac

        (( ++idx ))
    done
}

_xj_collect_ssh_known_hosts() {
    emulate -L zsh

    local known_host_file line raw_host host
    local -a known_host_files

    known_host_files=(/etc/ssh/ssh_known_hosts ~/.ssh/known_hosts)
    for known_host_file in "${known_host_files[@]}"; do
        [[ -r "$known_host_file" ]] || continue

        while IFS= read -r line || [[ -n "$line" ]]; do
            raw_host="${line%%[ |#]*}"
            [[ -n "$raw_host" ]] || continue

            for host in ${(s:,:)raw_host}; do
                if [[ "$host" == \[*\]:* ]]; then
                    host="${host#\[}"
                    host="${host%%\]:*}"
                fi
                _xj_should_complete_default_ssh_host "$host" || continue
                hosts+=("$host")
            done
        done < "$known_host_file"
    done
}

_xj_collect_etc_hosts() {
    emulate -L zsh

    local hosts_file_line host
    local -a fields

    [[ -r /etc/hosts ]] || return 0

    while IFS= read -r hosts_file_line || [[ -n "$hosts_file_line" ]]; do
        hosts_file_line="${hosts_file_line%%\#*}"
        fields=(${(z)hosts_file_line})
        (( ${#fields} >= 2 )) || continue

        for host in "${fields[2,-1]}"; do
            _xj_should_complete_default_ssh_host "$host" || continue
            hosts+=("$host")
        done
    done < /etc/hosts
}

_xj_ssh_completion_hosts_style() {
    emulate -L zsh

    local config_file="${XJ_SSH_CONFIG_FILE:-$HOME/.ssh/config}"
    local -Ua hosts=()
    local -A seen_files=()

    _xj_collect_ssh_config_hosts_from_file "$config_file"
    _xj_collect_ssh_known_hosts
    _xj_collect_etc_hosts

    reply=("${hosts[@]}")
}

#
# --- Plugins + starship + ghostty nt() (was 30-plugins.zsh) ---
#
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
    _xj_cache_tool_init atuin -- env ATUIN_NOBIND=true atuin init zsh || return 0

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

    # Load cached Starship prompt silently; the config file is an extra
    # staleness input because editing it must regenerate the init.
    _xj_cache_tool_init starship "$HOME/.config/starship.toml" -- starship init zsh

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

#
# --- Keybindings + utils (was 40-interactive.zsh) ---
#
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

#
# --- init() and its invocation (was 50-init.zsh) ---
#
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
    setup_utils

    if (( ! ${_XJ_KEYBINDINGS_READY:-0} )); then
        setup_keybindings
    fi

    # Source bun completion after compinit finishes (PATH set in .zprofile).
    [[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
}

init

#
# --- OpenClaw + zoxide post-init (was 60-post-init.zsh) ---
#
# OpenClaw completion
if [[ -r "$HOME/.openclaw/completions/openclaw.zsh" ]]; then
    source "$HOME/.openclaw/completions/openclaw.zsh"
fi

# Initialize zoxide last so it can install its hooks cleanly.
# Keep interactive mode light; the shared FZF preview is too heavy here.
export _ZO_DOCTOR=0
export _ZO_FZF_OPTS='--height 60% --layout reverse --border top --extended --no-sort'
_xj_cache_tool_init zoxide -- zoxide init zsh --cmd j
