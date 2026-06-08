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
