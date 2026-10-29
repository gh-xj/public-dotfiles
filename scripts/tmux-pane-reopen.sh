#!/usr/bin/env bash
# Browser-style close/reopen for tmux panes. Closing records the window, cwd and
# agent resume target (or older @claude_sid/@codex_sid), then kills the pane;
# reopening rebuilds the newest one and resumes the agent from its transcript.
set -euo pipefail
US=$'\x1f' RS=$'\x1e' KEEP=20 LIST=@closed_panes
# `display -t` falls back to the current window, so match ids exactly.
alive() { [[ $'\n'$(tmux list-windows -a -F "#{window_id}")$'\n' == *$'\n'"$1"$'\n'* ]]; }

case "${1:-}" in
close)
    pane=$2
    window=$(tmux display -p -t "$pane" "#{window_id}")
    [[ "$window" == @* ]] || exit 1 # a missing target formats as empty, not an error
    # A dead pane has no current path; fall back to where it started.
    entry=$(tmux display -p -t "$pane" "#{window_id}$US#{?pane_current_path,#{pane_current_path},#{pane_start_path}}$US#{?@resume_target,#{@resume_target},#{?@claude_sid,claude #{@claude_sid},#{?@codex_sid,codex #{@codex_sid},}}}")
    # Fields must not contain the separators or other control characters.
    if [[ "${entry//"$US"/}" != *[[:cntrl:]]* ]]; then
        IFS=$RS read -r -a old <<<"$(tmux show -gqv "$LIST")"
        list=$entry
        for item in "${old[@]:0:KEEP-1}"; do list+=$RS$item; done
        tmux set -g "$LIST" "$list"
    fi
    tmux kill-pane -t "$pane"
    if alive "$window"; then tmux select-layout -t "$window" -E; fi
    ;;
reopen)
    client=$2 session=$3
    list=$(tmux show -gqv "$LIST")
    if [[ -z "$list" ]]; then
        tmux display -c "$client" "no closed pane to reopen"
        exit 0
    fi
    entry=${list%%"$RS"*}
    rest=${list#"$entry"}
    IFS=$US read -r window cwd target <<<"$entry"
    [[ -d "$cwd" ]] || cwd=$HOME
    if alive "$window"; then
        create=(split-window -t "$window" -h)
    else
        create=(new-window -t "$session:")
    fi
    if ! pane=$(tmux "${create[@]}" -P -F "#{pane_id}" -c "$cwd"); then
        tmux display -c "$client" "could not create pane; closed pane record kept"
        exit 1
    fi
    # Only consume the record after creation succeeds, so failures are retryable.
    tmux set -g "$LIST" "${rest#"$RS"}"
    if [[ ${create[0]} == split-window ]]; then tmux select-layout -t "$pane" -E; fi
    if [[ -n "$target" ]]; then # RESUME_ENGINE (Nix-prepended) validates and applies the shared adapters
        tmux set -p -t "$pane" @resume_target "$target"
        TMUX_PANE=$pane "${RESUME_ENGINE[@]}" resume >/dev/null || tmux display -c "$client" "agent resume failed: $target"
    fi
    tmux switch-client -c "$client" -t "$pane"
    ;;
*)
    echo "usage: tmux-pane-reopen close PANE | reopen CLIENT SESSION" >&2
    exit 2
    ;;
esac
