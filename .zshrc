typeset -g _XJ_ZSHRC_FILE="${${(%):-%x}:A}"
typeset -g _XJ_ZSH_MODULE_DIR="${_XJ_ZSHRC_FILE:h}/.zsh/interactive"

_xj_source_zsh_module() {
    local module="$1"
    local source_file="${_XJ_ZSH_MODULE_DIR}/${module}"

    if [[ ! -r "$source_file" ]]; then
        printf 'missing zsh module: %s\n' "$source_file" >&2
        return 1
    fi

    source "$source_file"
}

# Ensure Ghostty shell integration also loads in shells spawned later by
# multiplexers (e.g. tmux), so command-finish notifications still work.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration" ]]; then
    source "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
fi

_xj_source_zsh_module 10-aliases.zsh

if [[ "${ZSH_MINIMAL:-0}" == 1 ]]; then
    return 0
fi

_xj_source_zsh_module 20-completion.zsh
_xj_source_zsh_module 30-plugins.zsh
_xj_source_zsh_module 40-interactive.zsh
_xj_source_zsh_module 50-init.zsh
_xj_source_zsh_module 60-post-init.zsh

unset _XJ_ZSHRC_FILE _XJ_ZSH_MODULE_DIR
unfunction _xj_source_zsh_module
