# Restore the complete declared PATH after macOS path_helper, including overlays.
if [[ -n "${PUBLIC_DOTFILES_STARTUP_PATH:-}" ]]; then
    export PATH="$PUBLIC_DOTFILES_STARTUP_PATH"
fi
[[ -o interactive ]] || unset PUBLIC_DOTFILES_STARTUP_PATH

# Environment variables and terminal configuration
setup_environment() {
    # Core environment
    export EDITOR='nvim'
    export VISUAL='nvim'
    export GIT_EDITOR='nvim'
    export HOMEBREW_AUTO_UPDATE_SECS=604800

    # Ghostty exports TERMINFO to its app bundle. Codex doctor expects the
    # searchable directory list to contain only existing roots, so keep the
    # directory search explicit and remove stale Nix profile entries.
    local _terminfo_dir
    local -a _terminfo_dirs
    for _terminfo_dir in \
        "$HOME/.terminfo" \
        "/Applications/Ghostty.app/Contents/Resources/terminfo" \
        "/usr/share/terminfo"; do
        [[ -d "$_terminfo_dir" ]] && _terminfo_dirs+=("$_terminfo_dir")
    done
    if (( ${#_terminfo_dirs[@]} )); then
        export TERMINFO_DIRS="${(j.:.)_terminfo_dirs}"
    fi
    unset TERMINFO

    # Set XDG_CONFIG_HOME for launchctl (macOS)
    /bin/launchctl setenv XDG_CONFIG_HOME "$HOME/.config" 2>/dev/null || true
}

# Main initialization
init() {
    setup_environment
}

init
