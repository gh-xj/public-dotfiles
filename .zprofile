# Environment variables and path configuration
setup_environment() {
    # Core environment
    export EDITOR='nvim'
    export VISUAL='nvim'
    export GIT_EDITOR='nvim'
    export XDG_CONFIG_HOME="$HOME/.config"
    export GOPATH="$HOME/go"
    export BUN_INSTALL="$HOME/.bun"
    export HOMEBREW_AUTO_UPDATE_SECS=604800

    # sccache: shared Rust compiler cache on the 4T volume (see ~/.cargo/config.toml)
    export SCCACHE_DIR="/Volumes/xj-sandisk-4T/dev/.sccache"
    export SCCACHE_CACHE_SIZE="20G"

    # Initialize Homebrew (sets HOMEBREW_PREFIX, PATH, MANPATH, INFOPATH)
    # Cached to avoid ~30ms subprocess per login shell
    local _brew_cache="$HOME/.cache/brew-shellenv.zsh"
    local _brew_bin=""
    [[ -x /opt/homebrew/bin/brew ]] && _brew_bin="/opt/homebrew/bin/brew"
    [[ -z "$_brew_bin" && -x /usr/local/bin/brew ]] && _brew_bin="/usr/local/bin/brew"
    if [[ -n "$_brew_bin" ]]; then
        if [[ ! -f "$_brew_cache" ]] || [[ "$_brew_bin" -nt "$_brew_cache" ]]; then
            mkdir -p "$HOME/.cache"
            "$_brew_bin" shellenv > "$_brew_cache" 2>/dev/null
        fi
        source "$_brew_cache"
    fi

    # Dev tool bins (.local/bin is prepended in .zshenv)
    export PATH="$HOME/go/bin:$HOME/.cargo/bin:$BUN_INSTALL/bin:$PATH"

    # Remove duplicates (covers all PATH additions across zsh init files).
    # -g required so the tied-unique attribute sticks to the global PATH
    # instead of being scoped local to this function.
    typeset -gU PATH

    # Set XDG_CONFIG_HOME for launchctl (macOS)
    /bin/launchctl setenv XDG_CONFIG_HOME "$HOME/.config" 2>/dev/null || true
}

# External integrations and tools
setup_integrations() {
    # OrbStack Docker integration
    source ~/.orbstack/shell/init.zsh 2>/dev/null || :
}

# Main initialization
init() {
    setup_environment
    setup_integrations
}

init
