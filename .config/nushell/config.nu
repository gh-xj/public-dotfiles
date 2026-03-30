

# =======================================================================
# Nushell Configuration File
# Version: 0.104.0
# =======================================================================

# =======================================================================
# 1. CORE SETTINGS
# =======================================================================
$env.config = {
    show_banner: false
    edit_mode: vi
    buffer_editor: "zed"
    completions: {
        algorithm: "fuzzy"
    }

    # Cursor shapes for different vi modes
    cursor_shape: {
        emacs: line
        vi_insert: line
        vi_normal: block
    }
}

# =======================================================================
# 5. ALIASES
# =======================================================================
# alias ls = eza --group-directories-first --git --icons
alias tree = eza --tree --level=3 --icons

alias k = kubectl
alias t = tmux
alias lg = lazygit
alias ld = lazydocker
alias s = fastfetch

alias c = code
alias co = code .
alias b = zed .

alias ghcs = gh copilot suggest
alias ghce = gh copilot explain

# =======================================================================
# 2. MODULE IMPORTS
# =======================================================================


# Zoxide (https://github.com/ajeetdsouza/zoxide)
source ~/.zoxide.nu

# Atuin (https://docs.atuin.sh/guide/installation/)
source ~/.local/share/atuin/init.nu

# carapace (https://carapace-sh.github.io/carapace-bin/setup.html)
source ~/.cache/carapace/init.nu


# =======================================================================
# 4. KEYBINDINGS
# =======================================================================
$env.config.keybindings ++= [
    # Accept suggestion with Ctrl+F
    {
        name: accept_suggestion
        modifier: control
        keycode: char_f
        mode: [emacs, vi_normal, vi_insert]
        event: { send: historyhintcomplete }
    }
    # Atuin search with Ctrl+R
    {
        name: atuin
        modifier: control
        keycode: char_r
        mode: [emacs, vi_normal, vi_insert]
        event: { send: executehostcommand cmd: (_atuin_search_cmd) }
    }
    # Activate yazi with Ctrl+Y
    {
        name: activate_yazi
        modifier: control
        keycode: char_y
        mode: [emacs, vi_normal, vi_insert]
        event: { send: executehostcommand cmd: "y" }
    }
    # Open lazygit with Ctrl+G
    {
        name: lazygit
        modifier: control
        keycode: char_g
        mode: [emacs, vi_normal, vi_insert]
        event: { send: executehostcommand cmd: "lazygit" }
    }
]



# =======================================================================
# 6. CUSTOM FUNCTIONS
# =======================================================================
# File Search Utilities
def f [dir?: path] {
    let search_dir = if $dir == null { $env.HOME } else { $dir }
    let cmd = $"fd . ($search_dir)"
    cd $search_dir
    $env.FZF_DEFAULT_COMMAND = $cmd
    fzf
}

# Yazi File Manager with Directory Tracking
def --env y [...args] {
    let tmp = (mktemp -t "yazi-cwd.XXXXXX")
    $env.FZF_DEFAULT_OPTS =  '--extended --no-sort --reverse --preview "if test -d {}; then
        eza --all --color=always --icons=always --group-directories-first --no-quotes --tree --level=2 --long {}
    elif test -f {}; then
        (eza --all --color=always --icons=always --no-quotes -l {} &&
        echo \"\" &&
        (bat --style=numbers --color=always {} || cat {})) 2>/dev/null
    else
        echo \"File not found: {}\"
    fi" --preview-window="right:60%:wrap"'
    yazi ...$args --cwd-file $tmp
    let cwd = (open $tmp)
    if $cwd != "" and $cwd != $env.PWD {
        cd $cwd
    }
    rm -fp $tmp
}

# Testing Utilities
def run_tick_test [] {
    print "Benchmarking Shell startup time (50 runs)..."
    mut times = []

    for i in 1..50 {
        let cmd_output = (do -i { ^time -p nu -c exit } | complete)

        # Extract the real time with a simpler approach
        let time_lines = ($cmd_output.stderr | lines)
        let real_line = ($time_lines | where $it starts-with "real" | first)

        if $real_line != null {
            let sec = ($real_line | split row " " | last | into float)
            let ms = ($sec * 1000 | math round)
            $times = ($times | append $ms)
            print $"Run ($i): ($ms) ms"
        }
    }

    if ($times | length) > 0 {
        let sum = ($times | math sum)
        let count = ($times | length)
        let avg = ($sum / $count | math round)
        let min = ($times | math min)
        let max = ($times | math max)

        print "----------------------------------------"
        print $"Results: Avg: ($avg) ms | Min: ($min) ms | Max: ($max) ms"
        print "----------------------------------------"
    } else {
        print "No valid timing data collected."
    }
}

def "from env" []: string -> record {
  lines
    | split column '#'
    | get column1
    | where {|it| ($it | str length) > 0}
    | parse "{key}={value}"
    | update value {str trim -c '"'}
    | transpose -r -d
}

def load-dotenv [file: string] {
    if not ($file | path exists) {
        error $"File not found: ($file)"
        return
    }

    let config = (open --raw $file | from env)
    load-env $config

    # Count records using built-in length
    let count = ($config | columns | length)
    echo $"Loaded ($count) environment variables from ($file)"
}


def --env pipe-to-zed [] {
    # Get the input from the pipeline
    let input = $in

    # Create a temporary file with a meaningful name
    let tmp = (mktemp -t "zed-pipe.XXXXXX")

    # Handle different input types appropriately
    if ($input | describe) starts-with "table" {
        # Tables need special formatting to display nicely
        $input | to text | save -f $tmp
    } else {
        # Direct save for strings and other types
        $input | save -f $tmp
    }

    # Open the file with Zed
    zed $tmp

    # Inform user about the temporary file location
    echo $"Output saved to ($tmp)"
}


def --env cd-parent [file_path: string] {
    let parent_dir = ($file_path | path dirname)
    cd $parent_dir
}

