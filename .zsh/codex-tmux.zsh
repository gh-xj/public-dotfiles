# The shared Codex app server may not inherit the launching pane environment.
# Pass per-invocation values through the supported command environment policy.
# The official standalone binary remains the executable owner.
codex() {
    if [[ -n "${TMUX:-}" && "${TMUX_PANE:-}" == %<-> ]]; then
        local socket_value
        socket_value=$(printf '%s' "$TMUX" | jq -Rs .) || return
        command codex \
            -c "shell_environment_policy.set.TMUX=$socket_value" \
            -c "shell_environment_policy.set.TMUX_PANE=\"$TMUX_PANE\"" \
            -c 'tui.terminal_title=[]' \
            "$@"
    else
        command codex "$@"
    fi
}
