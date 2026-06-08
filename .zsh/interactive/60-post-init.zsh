# OpenClaw completion
if [[ -r "$HOME/.openclaw/completions/openclaw.zsh" ]]; then
    source "$HOME/.openclaw/completions/openclaw.zsh"
fi

# Initialize zoxide last so it can install its hooks cleanly.
# Keep interactive mode light; the shared FZF preview is too heavy here.
export _ZO_DOCTOR=0
export _ZO_FZF_OPTS='--height 60% --layout reverse --border top --extended --no-sort'
if (( $+commands[zoxide] )); then
    _zoxide_cache="$HOME/.cache/zoxide-init.zsh"
    _zoxide_bin="$commands[zoxide]"
    if [[ ! -f "$_zoxide_cache" || "$_zoxide_bin" -nt "$_zoxide_cache" ]]; then
        mkdir -p "$HOME/.cache"
        "$_zoxide_bin" init zsh --cmd j >| "$_zoxide_cache" 2>/dev/null
    fi
    [[ -r "$_zoxide_cache" ]] && source "$_zoxide_cache" 2>/dev/null
fi
unset _zoxide_cache _zoxide_bin
