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

    local fzf_bin="${commands[fzf]:-}"
    if [[ -n "$fzf_bin" ]]; then
        local fzf_cache="$HOME/.cache/fzf-init.zsh"
        if [[ ! -f "$fzf_cache" || "$fzf_bin" -nt "$fzf_cache" ]]; then
            mkdir -p "$HOME/.cache"
            "$fzf_bin" --zsh >| "$fzf_cache" 2>/dev/null || true
        fi
        [[ -r "$fzf_cache" ]] && source "$fzf_cache" 2>/dev/null
    fi

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
