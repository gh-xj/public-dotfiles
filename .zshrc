# OPENSPEC:START
# OpenSpec shell completions configuration
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit
# OPENSPEC:END

# Ensure Ghostty shell integration also loads in shells spawned later by
# multiplexers such as Zellij, so command-finish notifications still work.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration" ]]; then
    source "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
fi

# Aliases and basic shell behavior
setup_aliases() {
    export EDITOR='nvim'
    export VISUAL='nvim'

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
    alias c='code'
    alias co='code .'
    alias b='nvim .'

    # Alias/function completion support
    unalias zj 2>/dev/null
    unalias jz 2>/dev/null
    setopt complete_aliases
    jz() { zellij attach "$@"; }
    zj() { zellij "$@"; }
    compdef -d zj 2>/dev/null
    compdef -d jz 2>/dev/null
    compdef _zj_completion zj
    compdef _zj_session_completion jz

    t() {
        if (( $# == 0 )); then
            tmux attach || tmux
        else
            tmux "$@"
        fi
    }

    claude() {
        "$HOME/.claude-theme-sync.sh" "$@"
    }
}

# Dynamic completion for `jz <session>`
_zj_session_completion() {
    local -a sessions
    sessions=("${(@f)$(zellij list-sessions --short --no-formatting 2>/dev/null)}")
    sessions=("${sessions[@]:#}")
    if (( ${#sessions[@]} > 0 )); then
        _values 'zellij session' ${sessions[@]}
    fi
}

_zj_completion() {
    if (( CURRENT >= 2 && words[2] == "attach" )); then
        _zj_session_completion
        return 0
    fi

    _zellij
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
    export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
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

    # Configure zsh-vi-mode cursor shapes
    export ZVM_CURSOR_STYLE_ENABLED=true
    export ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BEAM
    export ZVM_NORMAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
    export ZVM_VISUAL_MODE_CURSOR=$ZVM_CURSOR_BLOCK
    export ZVM_VISUAL_LINE_MODE_CURSOR=$ZVM_CURSOR_BLOCK
    export ZVM_OPPEND_MODE_CURSOR=$ZVM_CURSOR_BLINKING_UNDERLINE

    # Custom config function for zsh-vi-mode
    zvm_config() {
        ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
    }

    # Load essential plugins
    zinit wait'0a' lucid light-mode for \
        atinit"ZVM_INIT_MODE=sourcing" jeffreytse/zsh-vi-mode \
        Aloxaf/fzf-tab \
        atload"_zsh_autosuggest_start" zsh-users/zsh-autosuggestions \
        hlissner/zsh-autopair \
        MichaelAquilina/zsh-you-should-use

    # Init zoxide with --cmd j to avoid zi/zinit alias conflict
    # Creates `j` (jump) and `ji` (interactive) commands
    export _ZO_FZF_OPTS="$FZF_DEFAULT_OPTS"
    eval "$(zoxide init zsh --cmd j)"

    # Load atuin before syntax highlighting to avoid widget conflicts
    zinit wait'0c' lucid light-mode for \
        atinit"export ATUIN_NOBIND='true'" atload"bindkey '^r' atuin-search" atuinsh/atuin

    # Load syntax highlighting last to avoid conflicts
    zinit wait'0d' lucid light-mode for \
        atinit"zicompinit; zicdreplay" zdharma-continuum/fast-syntax-highlighting

    # Load cached Starship prompt silently
    if [[ ! -f ~/.cache/starship-init.zsh ]] || [[ ~/.config/starship.toml -nt ~/.cache/starship-init.zsh ]]; then
        mkdir -p ~/.cache
        starship init zsh > ~/.cache/starship-init.zsh 2>/dev/null
    fi
    source ~/.cache/starship-init.zsh 2>/dev/null

    # Reset terminal title to current directory before each prompt and
    # surface agent sessions more clearly inside Zed terminals.
    _set_terminal_title_literal() { printf '\033]2;%s\007' "$1" }
    _set_terminal_title() {
        [[ -n "$TMUX" ]] && return 0
        print -Pn "\e]2;%~\a"
    }
    _git_repo_title() {
        local root="${$(git rev-parse --show-toplevel 2>/dev/null):-}"
        [[ -n "$root" ]] && print -r -- "${root:t}" || print -r -- "${PWD:t}"
    }
    _git_branch_title() {
        git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
    }
    _set_agent_terminal_title() {
        [[ -n "$TMUX" ]] && return 0
        [[ -n "${ZED_TERM:-}" ]] || return 0

        local -a words
        local word tool repo branch title
        words=(${(z)1})

        for word in "${words[@]}"; do
            case "$word" in
                *=*|env|command|noglob) continue ;;
                claude|*/claude) tool="claude"; break ;;
                codex|*/codex) tool="codex"; break ;;
                *) break ;;
            esac
        done

        [[ -n "$tool" ]] || return 0

        repo="$(_git_repo_title)"
        branch="$(_git_branch_title)"
        title="$tool $repo"
        [[ -n "$branch" ]] && title+=":$branch"
        _set_terminal_title_literal "$title"
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

    add-zsh-hook preexec _set_agent_terminal_title
    add-zsh-hook precmd _set_terminal_title
}

# Lazy loading for heavy tools
setup_lazy_loading() {
    # NVM lazy loading
    nvm() {
        unfunction nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm "$@"
    }

    # Conda lazy loading (uses cached hook from .zshenv)
    conda() {
        unfunction conda
        source "$HOME/.cache/conda-hook.zsh" 2>/dev/null || {
            echo "Conda: cache missing, regenerating..."
            /opt/homebrew/Caskroom/miniforge/base/bin/conda shell.zsh hook > "$HOME/.cache/conda-hook.zsh" 2>/dev/null
            source "$HOME/.cache/conda-hook.zsh"
        }
        conda "$@"
    }
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
    # Enhanced file navigation
    f() {
        local dir="${1:-$HOME}"
        FZF_DEFAULT_COMMAND="fd . $dir" fzf
    }

    function y() {
        local FZF_DEFAULT_OPTS="--extended --no-sort --reverse --preview \"$_FZF_PREVIEW\" --preview-window=\"right:60%:wrap\""
    	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    	yazi "$@" --cwd-file="$tmp"
    	IFS= read -r -d '' cwd < "$tmp"
    	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    	rm -f -- "$tmp"
    }

    # Navigate to parent directory of file
    cd-parent() { cd "$(dirname "$1")"; }

    # Interactive ripgrep search
    rga() {
        local file
        file="$(FZF_DEFAULT_COMMAND="rga --files-with-matches '$1'" \
            fzf --preview="rga --pretty --context 5 {q} {}" --phony -q "$1" \
            --bind "change:reload:rga --files-with-matches {q}")" && open "$file"
    }

    # Load environment variables from file
    load-dotenv() {
        [[ ! -f "$1" ]] && echo "File not found: $1" && return 1
        local count=0
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^# ]] || [[ -z "$key" ]] && continue
            value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//')
            export "$key=$value"
            ((count++))
        done < "$1"
        echo "Loaded $count environment variables from $1"
    }

    # Pipe command output into the current editor.
    pipe-to-editor() {
        local tmp=$(mktemp -t "editor-pipe.XXXXXX")
        cat > "$tmp"
        "${EDITOR:-nvim}" "$tmp"
        echo "Output saved to $tmp"
    }
    alias pipe-to-nvim='pipe-to-editor'
    # Shell performance benchmarks using hyperfine
    alias benchmark_shell="hyperfine --warmup 3 --runs 10 'zsh -i -c exit'"
    alias benchmark_shell_quick="hyperfine 'zsh -i -c exit'"
    alias benchmark_shell_detailed="hyperfine --warmup 5 --runs 20 --show-output 'zsh -i -c exit'"
    alias benchmark_shells="hyperfine --warmup 2 'zsh -i -c exit' 'bash -i -c exit' 'fish -c exit' 'nu -c exit'"

}

# Agent bridge setup for Codex + Claude interoperability
setup_agent_bridges() {
    mkdir -p "$HOME/.agents/skills"

    if [[ ! -L "$HOME/.codex" ]]; then
        mkdir -p "$HOME/.codex"
    fi

    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
        ln -snf "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
    fi

    if [[ -d "$HOME/.claude/skills" ]]; then
        ln -snf "$HOME/.claude/skills" "$HOME/.agents/skills/claude-skills"
    fi

    # Optional superpowers bridge if installed
    if [[ -d "$HOME/.codex/superpowers/skills" ]]; then
        ln -snf "$HOME/.codex/superpowers/skills" "$HOME/.agents/skills/superpowers"
    fi
}

# Path setup (HOMEBREW_PREFIX already set by .zprofile via brew shellenv)
setup_paths() {
    # Homebrew completions
    if [[ -d "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions" ]]; then
        fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
    fi

    # Dev tool paths (.local/bin already set in .zshenv)
    export PATH="$HOME/go/bin:$HOME/.cargo/bin:$PATH"

    # Deduplicate PATH
    typeset -U PATH
}

# Main initialization
init() {
    # Set up paths (Homebrew already initialized in .zprofile)
    setup_paths

    setup_agent_bridges

    setup_plugins

    # Defer initialization until after vi-mode loads
    # setup_keybindings MUST run via zvm_after_init_commands (not earlier)
    # because zsh-vi-mode overrides keybindings during its initialization
    zvm_after_init_commands+=(
        'setup_aliases'
        'setup_fzf'
        'setup_lazy_loading'
        'setup_keybindings'  # MUST be after vi-mode to prevent override conflicts
        'setup_utils'
    )

    # Deferred completions and tool paths (zinit turbo-loaded after compinit)
    # ZeroClaw completions (cached, background-regenerated)
    if [[ ! -f ~/.cache/zeroclaw-completion.zsh ]] || [[ "$(command -v zeroclaw)" -nt ~/.cache/zeroclaw-completion.zsh ]]; then
        zeroclaw completions zsh > ~/.cache/zeroclaw-completion.zsh 2>/dev/null &!
    fi
    # Bun
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    # Defer completion/runtime snippets together to avoid loading `null` twice
    zinit wait'0e' lucid light-mode as'null' for \
        atinit'[[ -f ~/.cache/zeroclaw-completion.zsh ]] && source ~/.cache/zeroclaw-completion.zsh; \
              [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"' zdharma-continuum/null

}

init

# Ensure AI notification wrappers are only active in interactive Zed terminal sessions.
if [[ -o interactive && -n "${ZED_NOTIFY_TERMINAL:-}" ]]; then
    zed_notify_terminal() {
        ~/.config/zed/scripts/zed-notify-terminal.sh "$@"
    }

    codex() {
        zed_notify_terminal codex "$@"
    }

    claude() {
        zed_notify_terminal "$HOME/.claude-theme-sync.sh" "$@"
    }

    claude-code() {
        zed_notify_terminal "$HOME/.claude-theme-sync.sh" "$@"
    }
fi
