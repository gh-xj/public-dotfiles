# env.nu
#
# Installed by:
# version = "0.105.1"
#
# Previously, environment variables were typically configured in `env.nu`.
# In general, most configuration can and should be performed in `config.nu`
# or one of the autoload directories.
#
# This file is generated for backwards compatibility for now.
# It is loaded before config.nu and login.nu
#
# See https://www.nushell.sh/book/configuration.html
#
# Also see `help config env` for more options.
#
# You can remove these comments if you want or leave
# them for future reference.

$env.FZF_DEFAULT_OPTS = '--height 60% --tmux bottom,60% --layout reverse --border top'
$env.FZF_DEFAULT_COMMAND = 'fd --max-depth 1 --hidden --follow --exclude ".git" --exclude "node_modules"'
$env.FZF_CTRL_T_COMMAND = 'rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*" 2> /dev/null'
$env.FZF_ALT_C_COMMAND = "rg --sort-files --files --null 2> /dev/null | xargs -0 dirname | sort -u"
# Atuin (Shell History)
$env.ATUIN_NOBIND = true

use std "path add"
path add "~/.local/bin"
path add "/opt/homebrew/bin/brew"

# Setup Go bin path
if ("~/go/bin" | path exists) {
    path add "~/go/bin"
}

# use ~/.config/nushell/custom-completions/git/git-completions.nu *
# use ~/.config/nushell/custom-completions/<command>-completions.nu *

let homebrew_prefix = if ("/home/linuxbrew/.linuxbrew" | path exists) {
    # Linux
    "/home/linuxbrew/.linuxbrew"
} else if ("/opt/homebrew" | path exists) {
    # MacOS
    "/opt/homebrew"
} else if ("/usr/local" | path exists) {
    # MacOS legacy
    "/usr/local"
}


$env.HOMEBREW_PREFIX = $homebrew_prefix

# for git-quick-stats
path add ($homebrew_prefix | path join "opt" "coreutils" "libexec" "gnubin")

# SETUP HOMEBREW ENVIRONMENT VARIABLES
$env.HOMEBREW_PREFIX = $homebrew_prefix
$env.HOMEBREW_CELLAR = ($homebrew_prefix | path join "Cellar")
$env.HOMEBREW_REPOSITORY = if $homebrew_prefix == "/home/linuxbrew/.linuxbrew" {
    ($homebrew_prefix | path join "Homebrew")
} else {
    ($homebrew_prefix | path join "homebrew")
}
# Add to PATH using path add
path add ($homebrew_prefix | path join "bin")
path add ($homebrew_prefix | path join "sbin")
# Set MANPATH
if "MANPATH" not-in $env {
    $env.MANPATH = ""
}
let man_path = ($homebrew_prefix | path join "share" "man")
$env.MANPATH = if $env.MANPATH == "" {
    $man_path
} else {
    $"($man_path):($env.MANPATH)"
}
# Set INFOPATH
if "INFOPATH" not-in $env {
    $env.INFOPATH = ""
}
let info_path = ($homebrew_prefix | path join "share" "info")
$env.INFOPATH = if $env.INFOPATH == "" {
    $info_path
} else {
    $"($info_path):($env.INFOPATH)"
}

# lazygit (https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md)
$env.XDG_CONFIG_HOME = $"($env.HOME)/.config"

use std "path add"
path add "~/.local/bin"
path add "/opt/homebrew/bin/brew"
path add "~/go/bin"  # Add this line here

if not ("~/.zoxide.nu" | path exists) {
    zoxide init nushell --cmd j | save ~/.zoxide.nu
}

if not ("~/.local/share/atuin/init.nu" | path exists) {
    mkdir ~/.local/share/atuin/
    atuin init nu | save ~/.local/share/atuin/init.nu
}


# carapace-bin (https://carapace-sh.github.io/carapace-bin/setup.html)
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir ~/.cache/carapace
carapace _carapace nushell | save --force ~/.cache/carapace/init.nu
