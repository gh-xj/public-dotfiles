function core_parameters_init
    # -> Visual Tools
    function setup_alias_and_abbr
        alias ls='eza --group-directories-first --git --icons'
        alias ld='lazydocker'
        alias lg='lazygit'
        alias tree='eza --tree --level=3 --icons'
        alias s='fastfetch'

        # -> Development Shortcuts
        alias k='kubectl'
        alias t='tmux'
        alias c='code'
        alias co='code .'
        alias b='zed .'

        abbr -a -- - 'prevd'

        # append cd with eva
        # function cd
        #     builtin cd $argv && eza --group-directories-first --git --icons
        # end
    end
    setup_alias_and_abbr

    # -> FZF Configuration
    function setup_fzf
        set -gx FZF_DEFAULT_OPTS '--height 60% --tmux bottom,60% --layout reverse --border top'
        set -gx FZF_DEFAULT_COMMAND 'fd --max-depth 1 --hidden --follow --exclude ".git" --exclude "node_modules"'
        set -gx FZF_CTRL_T_COMMAND 'rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*" 2> /dev/null'
        set -gx FZF_ALT_C_COMMAND "rg --sort-files --files --null 2> /dev/null | xargs -0 dirname | sort -u"
    end
    setup_fzf

    function setup_brew
        if test -d /home/linuxbrew/.linuxbrew # Linux
           	set -gx HOMEBREW_PREFIX "/home/linuxbrew/.linuxbrew"
           	set -gx HOMEBREW_CELLAR "$HOMEBREW_PREFIX/Cellar"
           	set -gx HOMEBREW_REPOSITORY "$HOMEBREW_PREFIX/Homebrew"
        else if test -d /opt/homebrew # MacOS
           	set -gx HOMEBREW_PREFIX "/opt/homebrew"
           	set -gx HOMEBREW_CELLAR "$HOMEBREW_PREFIX/Cellar"
           	set -gx HOMEBREW_REPOSITORY "$HOMEBREW_PREFIX/homebrew"
        end
        fish_add_path -gP "$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin";
        ! set -q MANPATH; and set MANPATH ''; set -gx MANPATH "$HOMEBREW_PREFIX/share/man" $MANPATH;
        ! set -q INFOPATH; and set INFOPATH ''; set -gx INFOPATH "$HOMEBREW_PREFIX/share/info" $INFOPATH;
    end
    setup_brew

    function setup_go_bin
        if test -d "$HOME/go/bin"
            fish_add_path -gP "$HOME/go/bin"
        end
    end
    setup_go_bin

    function _fzf_compgen_path
        fd --hidden --follow --exclude ".git" . $argv[1]
    end

    function _fzf_compgen_dir
        fd --type d --hidden --follow --exclude ".git" . $argv[1]
    end

    # -> Search Utilities
    function rga
        set -l RG_PREFIX "rga --files-with-matches"
        set -l file (
            FZF_DEFAULT_COMMAND="$RG_PREFIX '$argv[1]'" \
            fzf --preview="rga --pretty --context 5 {q} {}" \
                --phony -q "$argv[1]" \
                --bind "change:reload:$RG_PREFIX {q}"
        )
        and open "$file"
    end

    function y
        set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
        set -x FZF_DEFAULT_OPTS '--extended --no-sort --reverse --preview "if test -d {}; then
            eza --all --color=always --icons=always --group-directories-first --no-quotes --tree --level=2 --long {}
        elif test -f {}; then
            (eza --all --color=always --icons=always --no-quotes -l {} &&
            echo \"\" &&
            (bat --style=numbers --color=always {} || cat {})) 2>/dev/null
        else
            echo \"File not found: {}\"
        fi" --preview-window="right:60%:wrap"'
        yazi $argv --cwd-file="$tmp"
        if test -s "$tmp"
            set -l cwd (cat -- "$tmp")
            if test -n "$cwd" -a "$cwd" != "$PWD"
                cd -- "$cwd"
            end
        end
        rm -f -- "$tmp"
    end

    function f
        set -l dir $argv[1]
        test -z "$dir"; and set dir $HOME
        if test -d "$dir"
            set -gx FZF_DEFAULT_COMMAND "fd . $dir"
        else
            set -gx FZF_DEFAULT_COMMAND "fd . $HOME"
        end
        fzf
    end
end

function core_pragram_init
    # Helper function to initialize tools with caching
    function __init_tool
        set -l name $argv[1]
        set -l cmd $argv[2]
        set -l cache_file ~/.cache/$name.fish

        # Only regenerate cache if it doesn't exist (remove the dependency checking)
        if not test -f $cache_file
            mkdir -p ~/.cache
            eval $cmd > $cache_file
        end

        source $cache_file
    end

    # Initialize all tools, param[0]: name; param[1]: command; param[2]: dependency file (optional)
    set -gx ATUIN_NOBIND 'true'
    __init_tool "atuin" "atuin init fish"
    __init_tool "fzf" "fzf --fish"
    __init_tool "zoxide" "zoxide init fish --cmd j"


    # NOTE: starship is replaced by hydro, so we don't need to initialize it here
    # __init_tool "starship" "starship init fish"


    # Clean up
    functions -e __init_tool
end

function setup_completions
    # NOTE: taskfile completion [Installation | Task](https://taskfile.dev/installation/)
    # task --completion fish > ~/.config/fish/completions/task.fish
    # __init_tool "task" "task --completion fish"

    # Orbstack initialization
    test -f ~/.orbstack/shell/init.fish; and source ~/.orbstack/shell/init.fish
end

function lazy_load_components_init
    # -> Node Version Manager
    function nvm
        functions -e nvm
        set -gx NVM_DIR "$HOME/.nvm"
        if test -s "$NVM_DIR/nvm.sh"
            bass source "$NVM_DIR/nvm.sh"
        end
        nvm $argv
    end

    # Hydro config (https://github.com/jorgebucaran/hydro?tab=readme-ov-file#configuration)
    function setup_hydro
        set -g hydro_symbol_start "\n"
        set -g hydro_symbol_start "aa"
        set -g hydro_symbol_git_dirty " 🧹"
        set -g hydro_color_pwd red
        set -g hydro_color_git green
        set -g hydro_color_duration yellow
        set -g fish_prompt_pwd_dir_length 2
    end
    setup_hydro

    function use_starship
        starship init fish | source
        echo "Switched to Starship prompt"
    end

    # -> Python Environments
    function my_conda
        # >>> conda initialize >>>
        # !! Contents within this block are managed by 'conda init' !!
        if test -f /opt/homebrew/Caskroom/miniforge/base/bin/conda
            eval /opt/homebrew/Caskroom/miniforge/base/bin/conda "shell.fish" "hook" $argv | source
        end
    end
end

function init_my_customized_utils

    function envsource
      for line in (cat $argv | grep -v '^#' |  grep -v '^\s*$' | sed -e 's/=/ /' -e "s/'//g" -e 's/"//g' )
        set export (string split ' ' $line)
        set -gx $export[1] $export[2]
        echo "Exported key $export[1]"
      end
    end

    function copy_last_output
      set PREV_CMD (history | head -1)
      set PREV_OUTPUT (eval $PREV_CMD)
      # use fish_clipboard_copy
        if test -n "$PREV_OUTPUT"
            echo -n "$PREV_OUTPUT" | fish_clipboard_copy
            echo "Copied last command output to clipboard."
        else
            echo "No output to copy."
        end
    end


    function copy_prev_cmd
        set PREV_CMD (history | head -1)
        if test -n "$PREV_CMD"
            echo -n "$PREV_CMD" | fish_clipboard_copy
            echo "Copied last command to clipboard."
        else
            echo "No previous command to copy."
        end
    end

    function run_tick_test
        echo "Benchmarking Fish shell startup time (10 runs)..."
        set -l times

        for i in (seq 50)
            set -l cmd_output (command time -p fish -ic exit 2>&1)
            set -l real_time (string match -r "real\s+([0-9.]+)" $cmd_output)

            if set -q real_time[2]
                set -l ms (math "round($real_time[2] * 1000)")
                set -a times $ms
                echo "Run $i: $ms ms"
            end
        end

        if test (count $times) -gt 0
            set -l sum (math (string join "+" $times))
            set -l avg (math "round($sum / "(count $times)")")
            set -l min (math "min("(string join "," $times)")")
            set -l max (math "max("(string join "," $times)")")

            echo "----------------------------------------"
            echo "Results: Avg: $avg ms| Min: $min ms | Max: $max ms "
            echo "----------------------------------------"
        else
            echo "No valid timing data collected."
        end
    end
end

function fish_user_setting
    set -gx fish_greeting

    # Enable vi mode
    fish_vi_key_bindings

    # Make Ctrl+F accept the autosuggestion (like right arrow)
    bind -M insert \cf forward-char
    # Also add it to normal mode if you want
    bind -M default \cf forward-char

    # bind to ctrl-r in normal and insert mode, add any other bindings you want here too
    bind \cr _atuin_search
    bind -M insert \cr _atuin_search
    bind -M default \cr _atuin_search

    # bind ctrl-g to activate lazygit
    bind -M insert \cg "commandline ''; lazygit; commandline -f repaint"
    bind -M default \cg "commandline ''; lazygit; commandline -f repaint"

    # bind ctrl-y to activate yazi
    bind -M insert \cy "commandline ''; y; commandline -f repaint"
    bind -M default \cy "commandline ''; y; commandline -f repaint"

    # # bind tab to complete-and-search
    # bind \t complete-and-search
    # bind -M default \t complete-and-search
    # bind -M insert \t complete-and-search

    # # bind shift+tab to complete
    # bind shift-\t complete
    # bind -M default shift-\t complete

    # NOTE: fisher is a plugin manager for Fish shell, use following commands to install plugins
    # `curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher`
    # fisher install jorgebucaran/hydro jorgebucaran/autopair.fish gazorby/fish-abbreviation-tips
    # fisher install dracula/fish

    # NOTE: You can use the following commands to view and then save themes
    # fish_config theme
    # fish_config theme save "Catppuccin Latte"

    # NOTE: fisher install ollehu/fifc

    # # Bind fzf completions to ctrl-x
    # set -U fifc_keybinding \cx
end

# ================================================
#  Main Initialization
# ================================================
function main

    core_parameters_init
    core_pragram_init
    setup_completions
    init_my_customized_utils
    lazy_load_components_init

    fish_user_setting
end


# ================================================
#  Execution
# ================================================
main
