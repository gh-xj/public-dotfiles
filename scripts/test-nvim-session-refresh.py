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
    config_home = root / "config"
    config_home.mkdir()
    os.environ["XDG_CONFIG_HOME"] = str(config_home)
    socket_name = f"nvim-refresh-{os.getpid()}"

    def tmux(*args, check=True):
        result = subprocess.run(["tmux", "-L", socket_name, *map(str, args)], capture_output=True, text=True)
        if check and result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout.rstrip("\n")

    try:
        pane = tmux("new-session", "-d", "-s", "refresh", "-c", root, "-P", "-F", "#{pane_id}", "bash", "--norc", "--noprofile")
        tmux("send-keys", "-t", pane, "-l", f"nvim -- {first}")
        tmux("send-keys", "-t", pane, "Enter")
        engine = refresh.Tmux(socket_name)
        candidates = []
        for _attempt in range(100):
            candidates, skipped = refresh.discover(engine, {pane})
            if candidates:
                break
            time.sleep(0.05)
        assert len(candidates) == 1 and skipped == []
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
        wrapped_candidates = []
        for _attempt in range(100):
            wrapped_candidates, _skipped = refresh.discover(engine, {wrapped})
            if wrapped_candidates:
                break
            time.sleep(0.05)
        old_pids = (wrapped_candidates[0]["tui_pid"], wrapped_candidates[0]["embed_pid"])
        wrapped_result = refresh.restart(engine, wrapped_candidates[0], 10)
        assert wrapped_result["method"] == "respawn-wrapper"
        assert all(pid not in refresh.process_table() for pid in old_pids)
        assert refresh.snapshot(wrapped_result["socket"])["tabs"][0]["file"] == str(third.resolve())

        rooted = tmux("new-window", "-d", "-t", "refresh:", "-c", root, "-P", "-F", "#{pane_id}", "nvim", "--", fourth)
        root_candidates = []
        for _attempt in range(100):
            root_candidates, _skipped = refresh.discover(engine, {rooted})
            if root_candidates:
                break
            time.sleep(0.05)
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
