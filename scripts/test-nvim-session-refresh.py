#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


sys.dont_write_bytecode = True
script = Path(__file__).with_name("nvim-session-refresh.py")
spec = importlib.util.spec_from_file_location("refresh", script)
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


missing = {"cwd": "/tmp", "current": 1, "dirty": [], "tabs": [{"file": "/tmp/missing", "cursor": [1, 0], "windows": 1}]}
assert refresh.invalid_state_reason(missing).startswith("tab file is unavailable:")
assert refresh.invalid_state_reason(dict(missing, dirty=["/tmp/missing"])).startswith("unsaved buffers:")

with tempfile.TemporaryDirectory(prefix="nvim-refresh-fixture-") as temporary:
    root = Path(temporary)
    first, second, third, fourth = (root / name for name in ("first.md", "second.md", "third.md", "fourth.md"))
    for path, body in ((first, "first\n"), (second, "second\nline two\n"), (third, "third\n"), (fourth, "fourth\n")):
        path.write_text(body)
    # Every XDG root, not just config: an editor started here must not read or write the
    # operator's real plugin, state and cache directories. A gate that mutates live editor
    # state is how breakage accumulates in a repository that declares it.
    live_state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    for variable, name in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                           ("XDG_STATE_HOME", "state"), ("XDG_CACHE_HOME", "cache")):
        (root / name).mkdir()
        os.environ[variable] = str(root / name)
    # `.zshenv` derives PATH from $XDG_STATE_HOME/nix/profiles/..., so a redirected state root
    # takes the profile - and with it tmux and nvim - off the respawned pane's PATH. Lend the
    # fixture the real profile and nothing else: editor state still lands in the temp root.
    (root / "state/nix").symlink_to(live_state / "nix")
    socket_name = f"nvim-refresh-{os.getpid()}"

    def tmux(*args, check=True):
        # -f /dev/null: the fixture server takes no configuration from the machine it runs on.
        result = subprocess.run(["tmux", "-f", "/dev/null", "-L", socket_name, *map(str, args)],
                                capture_output=True, text=True)
        if check and result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout.rstrip("\n")

    def await_candidate(target, attempts=100, pause=0.05):
        """Poll discover, and on timeout say what was seen: a hung editor, a timeout and a real
        discovery bug are otherwise one bare AssertionError."""
        found, skipped = [], []
        for _attempt in range(attempts):
            found, skipped = refresh.discover(engine, {target})
            if found:
                return found, skipped
            time.sleep(pause)
        raise AssertionError(f"no candidate in {target} after {attempts * pause:.1f}s; skipped={skipped}; "
                             f"pane ran {tmux('display-message', '-p', '-t', target, '#{pane_current_command}')!r}; "
                             f"pane contents:\n{tmux('capture-pane', '-p', '-t', target)}")

    try:
        pane = tmux("new-session", "-d", "-s", "refresh", "-c", root, "-P", "-F", "#{pane_id}", "bash", "--norc", "--noprofile")
        tmux("send-keys", "-t", pane, "-l", f"nvim -- {first}")
        tmux("send-keys", "-t", pane, "Enter")
        engine = refresh.Tmux(socket_name)
        candidates, skipped = await_candidate(pane)
        assert len(candidates) == 1 and skipped == [], f"candidates={candidates}; skipped={skipped}"
        original_embed = candidates[0]["embed_pid"]
        nvim_sock = candidates[0]["socket"]

        refresh.rpc(nvim_sock, f'luaeval("vim.cmd.tabedit(vim.fn.fnameescape(_A))", {json.dumps(str(second))})')
        refresh.rpc(nvim_sock, 'luaeval("vim.api.nvim_buf_set_lines(0,-1,-1,false,{_A})", "unsaved")')
        candidates, skipped = refresh.discover(engine, {pane})
        assert candidates == [] and len(skipped) == 1 and "unsaved buffers" in skipped[0]["reason"]
        planned = subprocess.run([sys.executable, str(script), "--socket", socket_name, "--pane", pane], capture_output=True, text=True)
        assert planned.returncode == 0 and engine.field(pane, "pane_pid") is not None

        refresh.rpc(nvim_sock, 'execute("write")')
        refresh.rpc(nvim_sock, 'luaeval("vim.api.nvim_win_set_cursor(0, _A)", [2,0])')
        engine.call("select-pane", "-t", pane, "-T", "fixture title")
        candidates, skipped = refresh.discover(engine, {pane})
        result = refresh.restart(engine, candidates[0], 10)
        assert result["embed_pid"] != original_embed and result["method"] == "shell"
        assert original_embed not in refresh.process_table()
        restored = refresh.snapshot(result["socket"])
        assert [tab["file"] for tab in restored["tabs"]] == [str(first.resolve()), str(second.resolve())]
        assert restored["current"] == 2 and restored["tabs"][1]["cursor"] == [2, 0]
        assert engine.field(pane, "pane_title") == "fixture title"
        assert engine.field(pane, "@recovery_document") == str(second.resolve())

        wrapper = root / "wrapper.py"
        wrapper.write_text("import subprocess,sys,time\nsubprocess.run(['nvim','--',sys.argv[1]])\ntime.sleep(60)\n")
        wrapped = tmux("new-window", "-d", "-t", "refresh:", "-c", root, "-P", "-F", "#{pane_id}", sys.executable, wrapper, third)
        wrapped_candidates, _skipped = await_candidate(wrapped)
        old_pids = (wrapped_candidates[0]["tui_pid"], wrapped_candidates[0]["embed_pid"])
        wrapped_result = refresh.restart(engine, wrapped_candidates[0], 10)
        assert wrapped_result["method"] == "respawn-wrapper"
        assert all(pid not in refresh.process_table() for pid in old_pids)
        assert refresh.snapshot(wrapped_result["socket"])["tabs"][0]["file"] == str(third.resolve())

        rooted = tmux("new-window", "-d", "-t", "refresh:", "-c", root, "-P", "-F", "#{pane_id}", "nvim", "--", fourth)
        root_candidates, _skipped = await_candidate(rooted)
        assert root_candidates[0]["tui_pid"] == root_candidates[0]["pane_pid"]
        root_old = (root_candidates[0]["tui_pid"], root_candidates[0]["embed_pid"])
        root_result = refresh.restart(engine, root_candidates[0], 10)
        assert root_result["method"] == "respawn-root" and engine.field(rooted, "pane_id") == rooted
        assert all(pid not in refresh.process_table() for pid in root_old)
        assert refresh.snapshot(root_result["socket"])["tabs"][0]["file"] == str(fourth.resolve())
    finally:
        try:
            leftovers, _skipped = refresh.discover(refresh.Tmux(socket_name))
            for entry in leftovers:
                refresh.run(["nvim", "--server", entry["socket"], "--remote-send", "<Esc>:qa<CR>"], check=False)
            for entry in leftovers:
                refresh.finish_old_processes(entry, 5)
        except (OSError, refresh.RefreshError, subprocess.SubprocessError):
            pass
        tmux("kill-server", check=False)

print("nvim session refresh plan, dirty guard and tab restoration fixtures passed")
