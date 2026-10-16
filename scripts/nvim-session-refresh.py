#!/usr/bin/env python3
"""Plan or safely refresh live Neovim sessions inside one tmux server."""

import argparse
import glob
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import time


SEPARATOR = "\x1f"
SHELLS = {"zsh", "bash", "fish", "sh", "dash", "nu"}
SNAPSHOT_EXPRESSION = (
    'luaeval("vim.json.encode((function() '
    "local dirty={} "
    "for _,buffer in ipairs(vim.fn.getbufinfo()) do "
    "if buffer.changed == 1 then table.insert(dirty,buffer.name) end end "
    "local tabs={} "
    "for _,tab in ipairs(vim.api.nvim_list_tabpages()) do "
    "local window=vim.api.nvim_tabpage_get_win(tab) "
    "local buffer=vim.api.nvim_win_get_buf(window) "
    "local windows=0 "
    "for _,candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do "
    "if vim.api.nvim_win_get_config(candidate).relative == '' then windows=windows+1 end end "
    "table.insert(tabs,{file=vim.api.nvim_buf_get_name(buffer),"
    "cursor=vim.api.nvim_win_get_cursor(window),windows=windows}) end "
    "return {cwd=vim.fn.getcwd(),current=vim.fn.tabpagenr(),dirty=dirty,tabs=tabs} "
    'end)())")'
)


class RefreshError(RuntimeError):
    pass


def run(argv, *, timeout=5, check=True):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise RefreshError(f"{' '.join(map(str, argv[:2]))} failed: {detail}")
    return result


def process_table():
    result = run(["ps", "-Aww", "-o", "pid=,ppid=,rss=,args="])
    table = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 3 or not all(part.isdigit() for part in parts[:3]):
            continue
        args = parts[3] if len(parts) == 4 else ""
        try:
            argv = shlex.split(args)
        except ValueError:
            argv = []
        table[int(parts[0])] = {"ppid": int(parts[1]), "rss": int(parts[2]), "args": args, "argv": argv}
    return table


def subtree(table, root):
    children = {}
    for pid, item in table.items():
        children.setdefault(item["ppid"], []).append(pid)
    found, stack = [], [root]
    while stack:
        pid = stack.pop()
        if pid not in found:
            found.append(pid)
            stack.extend(children.get(pid, []))
    return found


def nvim_socket(pid):
    base = os.environ.get("TMPDIR", "/tmp")
    matches = glob.glob(os.path.join(base, "nvim.*", "*", f"nvim.{pid}.0"))
    return matches[0] if len(matches) == 1 else ""


def rpc(socket, expression, timeout=3):
    return run(["nvim", "--server", socket, "--remote-expr", expression], timeout=timeout).stdout.rstrip("\n")


def snapshot(socket):
    try:
        value = json.loads(rpc(socket, SNAPSHOT_EXPRESSION))
    except (json.JSONDecodeError, OSError, RefreshError, subprocess.SubprocessError) as error:
        raise RefreshError(f"cannot read Neovim state; keep the pane open and rerun: {error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("tabs"), list) or not isinstance(value.get("dirty"), list):
        raise RefreshError("Neovim returned an invalid state snapshot; keep the pane open and rerun")
    return value


def invalid_state_reason(state):
    if state["dirty"]:
        names = ", ".join(name or "<unnamed>" for name in state["dirty"])
        return f"unsaved buffers: {names} -> write or discard them, then rerun"
    cwd = state.get("cwd", "")
    if not Path(cwd).is_dir():
        return f"working directory is unavailable: {cwd} -> restore it or :cd to an existing directory"
    if not state["tabs"]:
        return "no restorable tabs -> open a named file and rerun"
    for tab in state["tabs"]:
        name = tab.get("file", "") if isinstance(tab, dict) else ""
        cursor = tab.get("cursor", []) if isinstance(tab, dict) else []
        if not name or not Path(name).is_absolute():
            return "unnamed or relative tab -> save it to an absolute path or close it, then rerun"
        if not Path(name).is_file():
            return f"tab file is unavailable: {name} -> restore it or close that tab, then rerun"
        if tab.get("windows") != 1:
            return f"tab has {tab.get('windows', 0)} windows: {name} -> close extra splits or restart this pane manually"
        if not (isinstance(cursor, list) and len(cursor) == 2 and all(isinstance(value, int) for value in cursor)):
            return f"tab cursor is invalid for {name} -> close that tab and rerun"
    current = state.get("current")
    if not isinstance(current, int) or not 1 <= current <= len(state["tabs"]):
        return "current tab is invalid -> select a normal file tab and rerun"
    return ""


class Tmux:
    def __init__(self, socket=None):
        self.command = ["tmux"] + (["-L", socket] if socket else [])

    def call(self, *args, timeout=5, check=True):
        return run([*self.command, *map(str, args)], timeout=timeout, check=check)

    def text(self, *args, timeout=5):
        return self.call(*args, timeout=timeout).stdout.rstrip("\n")

    def field(self, pane, name):
        result = self.call("display-message", "-p", "-t", pane, "#{" + name + "}", check=False)
        return result.stdout.rstrip("\n") if result.returncode == 0 else None

    def panes(self):
        names = ("session_name", "window_index", "pane_id", "pane_pid", "pane_current_path", "pane_title", "pane_current_command")
        result = self.call("list-panes", "-a", "-F", SEPARATOR.join("#{" + name + "}" for name in names), check=False)
        if result.returncode:
            if "no server running" in result.stderr or "No such file" in result.stderr:
                return []
            raise RefreshError("cannot list tmux panes -> confirm the target server and rerun")
        rows = []
        for line in result.stdout.splitlines():
            parts = line.split(SEPARATOR)
            if len(parts) == len(names):
                rows.append(dict(zip(names, parts)))
        return rows


def find_servers(table, tree):
    found = []
    for pid in tree:
        argv = table.get(pid, {}).get("argv", [])
        if argv and Path(argv[0]).name == "nvim" and "--embed" in argv[1:]:
            socket = nvim_socket(pid)
            if socket:
                found.append((pid, socket))
    return found


def discover(tmux, selected=None):
    table = process_table()
    sessions, skipped = [], []
    for pane in tmux.panes():
        if selected and pane["pane_id"] not in selected:
            continue
        if not pane["pane_pid"].isdigit():
            continue
        servers = find_servers(table, subtree(table, int(pane["pane_pid"])))
        if not servers:
            continue
        where = f"{pane['session_name']}:{pane['window_index']} {pane['pane_id']}"
        if len(servers) != 1:
            skipped.append({"pane": where, "reason": "multiple Neovim servers in one pane -> close extras and rerun"})
            continue
        embed_pid, socket = servers[0]
        try:
            state = snapshot(socket)
            reason = invalid_state_reason(state)
        except RefreshError as error:
            state, reason = None, str(error)
        tui_pid = table.get(embed_pid, {}).get("ppid")
        process_ids = [pid for pid in (tui_pid, embed_pid) if isinstance(pid, int)]
        entry = {
            "pane": where,
            "pane_id": pane["pane_id"],
            "pane_pid": int(pane["pane_pid"]),
            "title": pane["pane_title"],
            "tui_pid": tui_pid,
            "embed_pid": embed_pid,
            "socket": socket,
            "rss_kib": sum(table.get(pid, {}).get("rss", 0) for pid in process_ids),
            "state": state,
            "process_args": {pid: table.get(pid, {}).get("args", "") for pid in process_ids},
        }
        if reason:
            skipped.append({"pane": where, "reason": reason})
        else:
            sessions.append(entry)
    return sessions, skipped


def public_entry(entry):
    state = entry["state"]
    return {
        "pane": entry["pane"],
        "tabs": len(state["tabs"]),
        "current_file": state["tabs"][state["current"] - 1]["file"],
        "rss_mib": round(entry["rss_kib"] / 1024, 1),
        "method": entry.get("method"),
    }


def wait_for_server(tmux, pane, old_socket, expected_file, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        root = tmux.field(pane, "pane_pid")
        if root and root.isdigit():
            table = process_table()
            for embed_pid, socket in find_servers(table, subtree(table, int(root))):
                if socket != old_socket:
                    try:
                        state = snapshot(socket)
                        entered = rpc(socket, "v:vim_did_enter") == "1"
                        first_loaded = bool(state["tabs"] and state["tabs"][0]["file"] == expected_file)
                        if entered and first_loaded:
                            return embed_pid, socket, table.get(embed_pid, {}).get("ppid")
                    except RefreshError:
                        pass
        time.sleep(0.1)
    raise RefreshError(f"new Neovim did not become ready in {timeout:g}s -> inspect pane {pane} and restart it manually")


def finish_old_processes(entry, timeout):
    """Wait for a clean editor to leave; terminate only exact stale identities."""
    expected = entry["process_args"]
    deadline = time.monotonic() + min(timeout, 2.0)
    while time.monotonic() < deadline:
        table = process_table()
        if not any(pid in table for pid in expected):
            return
        time.sleep(0.05)
    table = process_table()
    for pid, args in expected.items():
        if pid not in table:
            continue
        if table[pid]["args"] != args:
            raise RefreshError(f"old PID {pid} changed identity -> inspect it before retrying")
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + min(timeout, 2.0)
    while time.monotonic() < deadline:
        table = process_table()
        if not any(pid in table for pid in expected):
            return
        time.sleep(0.05)
    remaining = [str(pid) for pid in expected if pid in process_table()]
    if remaining:
        raise RefreshError(f"old clean Neovim PIDs did not exit: {','.join(remaining)} -> inspect and terminate them manually")


def restore_tabs(socket, state, timeout):
    tabs = state["tabs"]
    rpc(socket, f'luaeval("vim.api.nvim_win_set_cursor(0, _A)", {json.dumps(tabs[0]["cursor"])})', timeout)
    for tab in tabs[1:]:
        rpc(socket, f'luaeval("vim.cmd.tabedit(vim.fn.fnameescape(_A))", {json.dumps(tab["file"], ensure_ascii=False)})', timeout)
        rpc(socket, f'luaeval("vim.api.nvim_win_set_cursor(0, _A)", {json.dumps(tab["cursor"])})', timeout)
    rpc(socket, f'execute("tabnext {state["current"]}")', timeout)


def restart(tmux, entry, timeout):
    pane, old_socket = entry["pane_id"], entry["socket"]
    root = tmux.field(pane, "pane_pid")
    table = process_table()
    if not root or not root.isdigit() or entry["embed_pid"] not in subtree(table, int(root)):
        raise RefreshError("pane process tree changed after planning -> rerun the plan before applying")
    state = snapshot(old_socket)
    reason = invalid_state_reason(state)
    if reason:
        raise RefreshError(reason)
    nvim_command = shlex.join(["nvim", "--", state["tabs"][0]["file"]])
    if entry["tui_pid"] == entry["pane_pid"]:
        method = "respawn-root"
    else:
        run(["nvim", "--server", old_socket, "--remote-send", "<Esc>:qa<CR>"], check=False)
        deadline = time.monotonic() + timeout
        while Path(old_socket).exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        if Path(old_socket).exists():
            raise RefreshError("Neovim refused :qa -> close any prompt or blocking autocmd and rerun")
        finish_old_processes(entry, timeout)
        command = ""
        while time.monotonic() < deadline:
            command = tmux.field(pane, "pane_current_command")
            if command is None or command.lstrip("-") in SHELLS:
                break
            time.sleep(0.1)
        if command is None:
            raise RefreshError("tmux pane disappeared during refresh -> recreate it from the recorded file")
        method = "shell" if command.lstrip("-") in SHELLS else "respawn-wrapper"
    if method == "shell":
        command = f"cd -- {shlex.quote(state['cwd'])} && {nvim_command}"
        tmux.call("send-keys", "-t", pane, "C-c")
        tmux.call("send-keys", "-t", pane, "-l", command)
        tmux.call("send-keys", "-t", pane, "Enter")
    else:
        shell = tmux.text("show-options", "-gv", "default-shell")
        command = f"{nvim_command}; exec {shlex.quote(shell)} -l"
        tmux.call("respawn-pane", "-k", "-t", pane, "-c", state["cwd"], shell, "-ic", command)
        finish_old_processes(entry, timeout)
    embed_pid, socket, tui_pid = wait_for_server(tmux, pane, old_socket, state["tabs"][0]["file"], timeout)
    restore_tabs(socket, state, timeout)
    tmux.call("set-option", "-p", "-t", pane, "@recovery_document", state["tabs"][state["current"] - 1]["file"])
    tmux.call("select-pane", "-t", pane, "-T", entry["title"])
    restored = snapshot(socket)
    expected_files = [tab["file"] for tab in state["tabs"]]
    actual_files = [tab["file"] for tab in restored["tabs"]]
    if restored["dirty"] or actual_files != expected_files or restored["current"] != state["current"]:
        raise RefreshError(
            "postcheck did not match saved state "
            f"(tabs {len(expected_files)}->{len(actual_files)}, active {state['current']}->{restored['current']}) "
            "-> inspect the live pane; it was left running"
        )
    table = process_table()
    entry.update({
        "method": method,
        "tui_pid": tui_pid,
        "embed_pid": embed_pid,
        "socket": socket,
        "rss_kib_after": sum(table.get(pid, {}).get("rss", 0) for pid in (tui_pid, embed_pid)),
        "state": restored,
    })
    return entry


def main():
    parser = argparse.ArgumentParser(prog="nvim-session-refresh", description=__doc__)
    parser.add_argument("--apply", action="store_true", help="restart safe sessions; default is plan only")
    parser.add_argument("--pane", action="append", help="limit to a tmux pane id such as %%42; repeatable")
    parser.add_argument("--socket", help="tmux -L socket; defaults to the current/default server")
    parser.add_argument("--timeout", type=float, default=10.0, help="seconds to wait for each clean exit/start")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    selected = set(args.pane or [])
    if any(not re.fullmatch(r"%[0-9]+", pane) for pane in selected):
        parser.error("--pane must look like %42")
    tmux = Tmux(args.socket)
    try:
        candidates, skipped = discover(tmux, selected)
        if selected:
            found = {entry["pane_id"] for entry in candidates} | {item["pane"].rsplit(" ", 1)[-1] for item in skipped}
            for pane in sorted(selected - found):
                skipped.append({"pane": pane, "reason": "no reachable Neovim server -> select a live Neovim pane and rerun"})
        report = {
            "mode": "apply" if args.apply else "plan",
            "restartable": [public_entry(entry) for entry in candidates],
            "restarted": [],
            "skipped": skipped,
            "failed": [],
        }
        before = sum(entry["rss_kib"] for entry in candidates)
        if args.apply:
            report["restartable"] = []
            for entry in candidates:
                try:
                    report["restarted"].append(public_entry(restart(tmux, entry, args.timeout)))
                except (RefreshError, OSError, subprocess.SubprocessError) as error:
                    report["failed"].append({"pane": entry["pane"], "reason": str(error)})
        after = sum(entry.get("rss_kib_after", entry["rss_kib"]) for entry in candidates)
        report["summary"] = {
            "found": len(candidates) + len(skipped),
            "restartable": len(report["restartable"]),
            "restarted": len(report["restarted"]),
            "skipped": len(skipped),
            "failed": len(report["failed"]),
            "rss_mib_before": round(before / 1024, 1),
            "rss_mib_after": round(after / 1024, 1),
            "rss_mib_delta": round((after - before) / 1024, 1),
        }
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1 if args.apply and (report["skipped"] or report["failed"]) else 0
    except (RefreshError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"mode": "apply" if args.apply else "plan", "error": str(error)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
