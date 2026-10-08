#!/usr/bin/env python3
"""Versioned topology recovery. A bad pane, session or directory never costs the rest.

No scrollback, no recorded commands, no agent databases. Capture takes one
`list-panes -a` snapshot; restore builds each session independently and starts nothing.
"""
import argparse
import fcntl
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import time
import tomllib

FORMAT = "public-dotfiles.tmux-recovery"
VERSION = 1
PREFIX = "public-tmux-v1-"
DOCUMENT = "@recovery_document"
RESUME = "@resume_target"  # "<provider> <session_id>"; prompt hooks never clear it.
SEP = "\x1f"
SHELLS = {"zsh", "bash", "fish", "sh", "dash", "nu"}
BUILTINS = {
    "claude": {"option": "@claude_sid", "argv": ["claude", "--resume", "{session_id}"]},
    "codex": {"option": "@codex_sid", "argv": ["codex", "resume", "{session_id}"]},
}


class RecoveryError(ValueError):
    """Public, actionable validation messages without private checkpoint data."""


def text(value, maximum=4096):
    if not isinstance(value, str) or len(value) > maximum or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise RecoveryError("invalid text field")
    return value


def clean(value, maximum=4096):
    return "".join(c for c in value if c >= " " and c != "\x7f")[:maximum]


def session_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}", value):
        raise RecoveryError("invalid provider session ID")
    return value


def adapters(path=None):
    result = {key: dict(value) for key, value in BUILTINS.items()}
    if path:
        with open(path, "rb") as source:
            extra = tomllib.load(source) if str(path).endswith(".toml") else json.load(source)
        result.update(extra.get("adapters", extra))
    options = set()
    for name, entry in result.items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", name):
            raise RecoveryError("invalid provider name")
        option = entry["option"]
        if not re.fullmatch(r"@[a-z][a-z0-9_]*", option) or option in options or option in (DOCUMENT, RESUME, "@agent_label") or option.startswith("@workmux"):
            raise RecoveryError("invalid, reserved or duplicate provider option")
        options.add(option)
        argv = entry["argv"]
        if not isinstance(argv, list) or not argv or argv.count("{session_id}") != 1:
            raise RecoveryError("adapter requires one separate {session_id} argv element")
        for arg in argv:
            text(arg)
            if not arg or "{session_id}" in arg and arg != "{session_id}":
                raise RecoveryError("adapter session ID must be a separate argv element")
    return result


def digest(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def filename(record):
    return f'{PREFIX}{record["scope"]}-{record["created_ns"]}-{record["sha256"][:12]}.json'


def read_record(path, owned=False):
    if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode) or path.stat().st_size > 16 * 1024 * 1024:
        raise RecoveryError("checkpoint must be a bounded regular file")
    record = json.loads(path.read_text())
    if not isinstance(record, dict):
        raise RecoveryError("checkpoint must be an object")
    if record.get("format") != FORMAT or record.get("version") != VERSION:
        raise RecoveryError("unsupported checkpoint format; legacy files are not migrated automatically")
    if not re.fullmatch(r"all|session-[0-9a-f]{64}", record.get("scope", "")):
        raise RecoveryError("invalid scope")
    if not isinstance(record.get("created_ns"), int) or record["created_ns"] < 0 or digest(record["payload"]) != record.get("sha256"):
        raise RecoveryError("invalid checkpoint checksum or timestamp")
    validate_payload(record["payload"])
    if owned and path.name != filename(record):
        raise RecoveryError("not an engine-owned checkpoint")
    return record


def save(directory, scope, payload, keep_newest, keep_days):
    validate_payload(payload)
    if directory.is_symlink():
        raise RecoveryError("checkpoint directory must not be a symlink")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_fd = os.open(directory / ".public-tmux-recovery.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        records = []
        for path in directory.glob(PREFIX + "*.json"):
            try:
                records.append((path, read_record(path, owned=True)))
            except (OSError, ValueError, KeyError, TypeError):
                continue  # Unknown, malformed and legacy material is never collected.
        records.sort(key=lambda item: item[1]["created_ns"], reverse=True)
        same_scope = next((item for item in records if item[1]["scope"] == scope), None)
        checksum = digest(payload)
        changed = not same_scope or same_scope[1]["sha256"] != checksum
        if changed:
            record = {"format": FORMAT, "version": VERSION, "created_ns": time.time_ns(),
                      "scope": scope, "payload": payload, "sha256": checksum}
            path = directory / filename(record)
            with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as out:
                json.dump(record, out, ensure_ascii=False, indent=2)
                out.flush()
                os.fsync(out.fileno())
                temporary = Path(out.name)
            try:
                os.replace(temporary, path)  # NamedTemporaryFile is mode 0600.
            finally:
                temporary.unlink(missing_ok=True)
            records.insert(0, (path, record))
        else:
            path = same_scope[0]
        # A hard global cap; protect the current snapshot even if an unchanged
        # session has been idle longer than the age window. No legacy deletion.
        keep = {path}
        cutoff = time.time_ns() - keep_days * 86400 * 1_000_000_000
        for candidate, record in records:
            if len(keep) < keep_newest and record["created_ns"] >= cutoff:
                keep.add(candidate)
        removed = 0
        for candidate, _ in records:
            if candidate not in keep:
                candidate.unlink()
                removed += 1
        return {"file": str(path), "changed": changed, "pruned_owned_files": removed}


def log_run(directory, line):
    """One line per run; capped by dropping the oldest half when it grows large."""
    log = directory / "recovery.log"
    with open(log, "a") as out:
        out.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + line + "\n")
    if log.stat().st_size > 256 * 1024:
        lines = log.read_text().splitlines()
        log.write_text("\n".join(lines[len(lines) // 2:]) + "\n")


def validate_session(session):
    name = text(session["name"], 255)
    if not name or "." in name or ":" in name:
        raise RecoveryError("invalid target session name")
    windows = session["windows"]
    if not 1 <= len(windows) <= 512 or sum(w["active"] is True for w in windows) != 1:
        raise RecoveryError("invalid windows or active window")
    indices = set()
    for window in windows:
        index = window["index"]
        if type(index) is not int or index < 0 or index in indices:
            raise RecoveryError("invalid or duplicate window index")
        indices.add(index)
        text(window["name"])
        if not re.fullmatch(r"[0-9a-fA-F,{}\[\]x]+", window["layout"]):
            raise RecoveryError("invalid layout")
        if not all(type(window[k]) is int and 2 <= window[k] <= 10000 for k in ("width", "height")):
            raise RecoveryError("invalid window dimensions")
        panes = window["panes"]
        if not 1 <= len(panes) <= 256 or sum(p["active"] is True for p in panes) != 1:
            raise RecoveryError("invalid panes or active pane")
        pane_indices = [p["index"] for p in panes]
        if any(type(i) is not int or i < 0 for i in pane_indices) or pane_indices != sorted(set(pane_indices)):
            raise RecoveryError("invalid pane order")
        for pane in panes:
            if not Path(text(pane["cwd"])).is_absolute():
                raise RecoveryError("checkpoint working directory is missing")
            text(pane["title"]); text(pane["label"])
            if not isinstance(pane["providers"], dict):
                raise RecoveryError("invalid providers")
            for provider, identity in pane["providers"].items():
                text(provider, 32); text(identity["option"])
                session_id(identity["session_id"])
            if pane.get("document") and not Path(text(pane["document"])).is_absolute():
                raise RecoveryError("invalid or missing document path")


def validate_payload(payload):
    try:
        sessions = payload["sessions"]
        if not isinstance(sessions, list) or not 1 <= len(sessions) <= 256:
            raise RecoveryError("invalid session count")
        for session in sessions:
            validate_session(session)
        if len({s["name"] for s in sessions}) != len(sessions):
            raise RecoveryError("duplicate target session name")
    except (KeyError, TypeError, AttributeError) as error:
        raise RecoveryError("invalid checkpoint payload structure") from error


def process_table():
    """pid -> (ppid, cpu%, argv0 basename, args) from one `ps`."""
    out = subprocess.run(["ps", "-Aww", "-o", "pid=,ppid=,pcpu=,args="], capture_output=True, text=True).stdout
    table = {}
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) >= 3 and parts[0].isdigit() and parts[1].isdigit():
            args = parts[3] if len(parts) > 3 else ""
            table[int(parts[0])] = (int(parts[1]), float(parts[2]), os.path.basename(args.split(" ", 1)[0]), args)
    return table


def subtree(table, root):
    children = {}
    for pid, (ppid, *_rest) in table.items():
        children.setdefault(ppid, []).append(pid)
    found, stack = [], [root]
    while stack:
        pid = stack.pop()
        if pid in found:
            continue
        found.append(pid)
        stack.extend(children.get(pid, []))
    return found


def editors(table, pids):
    """(document, unsaved_buffers) per nvim reachable in the process tree, via its own server."""
    result = []
    base = os.environ.get("TMPDIR", "/tmp")
    for pid in pids:
        for sock in glob.glob(os.path.join(base, "nvim.*", "*", f"nvim.{pid}.0")):
            expr = "expand('%:p').\"\\t\".len(filter(getbufinfo(),'v:val.changed'))"
            try:
                got = subprocess.run(["nvim", "--server", sock, "--remote-expr", expr], capture_output=True, text=True, timeout=2).stdout
                document, _, unsaved = got.rpartition("\t")
                result.append((document, int(unsaved)))
            except (OSError, ValueError, subprocess.SubprocessError):
                continue
    return result


class Engine:
    def __init__(self, provider_map, socket=None):
        self.providers = provider_map
        self.command = ["tmux"] + (["-L", socket] if socket else [])
        self.warnings = []

    def tmux(self, *args):
        result = subprocess.run([*self.command, *map(str, args)], capture_output=True, text=True)
        if result.returncode:
            raise RecoveryError("tmux operation failed; any newly created sessions are left for inspection")
        return result.stdout.rstrip("\n")

    def field(self, target, name):
        return self.tmux("display-message", "-p", "-t", target, "#{" + name + "}")

    def exists(self, name):
        return subprocess.run([*self.command, "has-session", "-t", "=" + name], capture_output=True).returncode == 0

    def panes(self, *names):
        """Every pane in one tmux call: list of dicts keyed by the requested format names."""
        fmt = SEP.join("#{" + n + "}" for n in names)
        result = subprocess.run([*self.command, "list-panes", "-a", "-F", fmt], capture_output=True, text=True)
        if result.returncode:
            if "no server running" in result.stderr or "No such file or directory" in result.stderr:
                return []
            raise RecoveryError("cannot enumerate tmux panes")
        rows = []
        for line in result.stdout.splitlines():
            parts = line.split(SEP)
            if len(parts) == len(names):
                rows.append(dict(zip(names, parts)))
            else:
                self.warnings.append("dropped a pane row with unexpected fields")
        return rows

    def capture(self, name=None):
        options = [entry["option"] for entry in self.providers.values()]
        rows = self.panes("session_id", "session_name", "window_id", "window_index", "window_name", "window_layout",
                          "window_active", "pane_id", "pane_index", "pane_active", "pane_pid", "pane_current_path",
                          "pane_title", "@agent_label", RESUME, DOCUMENT, *options)
        table = process_table()
        sessions = {}
        for row in rows:
            if name is not None and row["session_name"] != name:
                continue
            session = sessions.setdefault(row["session_id"], {"name": row["session_name"], "windows": {}})
            window = session["windows"].setdefault(row["window_id"], {
                "name": clean(row["window_name"]), "index": int(row["window_index"]), "layout": row["window_layout"],
                "active": row["window_active"] == "1", "panes": []})
            providers = {}
            for provider, entry in self.providers.items():
                value = row[entry["option"]]
                if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}", value):
                    providers[provider] = {"option": entry["option"], "session_id": value}
                elif value:
                    self.warnings.append(f"dropped invalid {provider} id in {row['pane_id']}")
            target = row[RESUME].split(" ", 1)
            if len(target) == 2 and target[0] in self.providers and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}", target[1]):
                providers.setdefault(target[0], {"option": self.providers[target[0]]["option"], "session_id": target[1]})
            elif row[RESUME]:
                self.warnings.append(f"dropped unusable resume target in {row['pane_id']}")
            pane = {"index": int(row["pane_index"]), "cwd": row["pane_current_path"], "title": clean(row["pane_title"]),
                    "label": clean(row["@agent_label"]), "active": row["pane_active"] == "1", "providers": providers}
            if not pane["cwd"].startswith("/") or any(ord(c) < 32 for c in pane["cwd"]):
                self.warnings.append(f"{row['pane_id']} has no usable cwd; recorded ~")
                pane["cwd"] = str(Path.home())
            tree = subtree(table, int(row["pane_pid"])) if row["pane_pid"].isdigit() else []
            document = row[DOCUMENT] or next((d for d, _ in editors(table, tree) if d), "")
            if document.startswith("/") and not any(ord(c) < 32 for c in document) and len(document) <= 4096:
                pane["document"] = document
            window["panes"].append((row["pane_id"], pane))
        result = []
        for session in sessions.values():
            windows = []
            for window in session["windows"].values():
                pane_ids = {p[1:] for p, _ in window["panes"]}
                dimensions = re.match(r"^[0-9a-f]+,(\d+)x(\d+),", window["layout"])
                if not dimensions or set(re.findall(r"\d+x\d+,\d+,\d+,(\d+)", window["layout"])) != pane_ids:
                    self.warnings.append(f"dropped window {session['name']}:{window['index']} with an unreadable layout")
                    continue
                window["width"], window["height"] = map(int, dimensions.groups())
                panes = sorted((p for _, p in window["panes"]), key=lambda p: p["index"])
                if sum(p["active"] for p in panes) != 1:
                    for p in panes:
                        p["active"] = p is panes[0]
                window["panes"] = panes
                windows.append(window)
            if windows:
                windows.sort(key=lambda w: w["index"])
                if sum(w["active"] for w in windows) != 1:
                    for w in windows:
                        w["active"] = w is windows[0]
                result.append({"name": session["name"], "windows": windows})
            else:
                self.warnings.append(f"dropped session {session['name']} with no readable window")
        kept = []
        for session in sorted(result, key=lambda s: s["name"]):
            try:
                validate_session(session)
                kept.append(session)
            except (RecoveryError, KeyError, TypeError) as error:
                self.warnings.append(f"dropped session {session['name']}: {error}")
        return {"sessions": kept}

    def restore(self, payload, apply=False, prefix=""):
        """Per session: skip existing, fall back to ~ for a missing cwd, continue past failures."""
        report = {"mode": "apply" if apply else "plan", "restored": [], "skipped": [], "failed": [], "cwd_fallbacks": 0}
        for session in payload["sessions"]:
            name = prefix + str(session.get("name"))
            try:
                validate_session(session)
                if self.exists(name):
                    report["skipped"].append({"session": name, "reason": "exists"})
                    continue
                report["cwd_fallbacks"] += sum(not Path(p["cwd"]).is_dir() for w in session["windows"] for p in w["panes"])
                if apply:
                    self.build(name, session)
                report["restored"].append(name)
            except (RecoveryError, KeyError, TypeError, OSError, RuntimeError) as error:
                report["failed"].append({"session": name, "reason": str(error)})
        return report

    def build(self, name, session):
        parked = [sys.executable, str(Path(__file__).resolve()), "_park"]
        home = str(Path.home())
        where = lambda pane: pane["cwd"] if Path(pane["cwd"]).is_dir() else home
        first = session["windows"][0]
        pid = self.tmux("new-session", "-d", "-s", name, "-n", first["name"], "-c", where(first["panes"][0]),
                        "-x", max(w["width"] for w in session["windows"]), "-y", max(w["height"] for w in session["windows"]),
                        "-P", "-F", "#{pane_id}", *parked)
        sid = self.field(pid, "session_id")
        self.tmux("set-option", "-t", sid, "renumber-windows", "off")
        first_wid = self.field(pid, "window_id")
        if int(self.field(first_wid, "window_index")) != first["index"]:
            self.tmux("move-window", "-s", first_wid, "-t", sid + ":" + str(first["index"]))
        active_window = first_wid
        for number, window in enumerate(session["windows"]):
            if number:
                pid = self.tmux("new-window", "-d", "-t", sid + ":" + str(window["index"]), "-n", window["name"],
                                "-c", where(window["panes"][0]), "-P", "-F", "#{pane_id}", *parked)
            wid = self.field(pid, "window_id")
            self.tmux("set-option", "-w", "-t", wid, "automatic-rename", "off")
            self.tmux("set-option", "-w", "-t", wid, "remain-on-exit", "on")
            self.tmux("set-option", "-w", "-t", wid, "pane-base-index", window["panes"][0]["index"])
            self.tmux("resize-window", "-t", wid, "-x", window["width"], "-y", window["height"])
            active_pane = pid
            for pindex, pane in enumerate(window["panes"]):
                if pindex:
                    pid = self.tmux("split-window", "-d", "-h", "-t", pid, "-c", where(pane), "-P", "-F", "#{pane_id}", *parked)
                    self.tmux("select-layout", "-t", wid, "tiled")
                self.tmux("select-pane", "-t", pid, "-T", pane["title"])
                self.tmux("set-option", "-p", "-t", pid, "@agent_label", pane["label"])
                if len(pane["providers"]) == 1:
                    (provider, identity), = pane["providers"].items()
                    self.tmux("set-option", "-p", "-t", pid, RESUME, provider + " " + identity["session_id"])
                if pane.get("document"):
                    self.tmux("set-option", "-p", "-t", pid, DOCUMENT, pane["document"])
                if pane["active"]:
                    active_pane = pid
            self.tmux("select-layout", "-t", wid, window["layout"])
            self.tmux("select-pane", "-t", active_pane)
            if window["active"]:
                active_window = wid
        self.tmux("select-window", "-t", active_window)

    def resume(self, everything=False, delay=5.0, current=None):
        """Start recorded agents/editors in panes that are idle: never anything already running."""
        rows = self.panes("pane_id", "pane_current_command", "pane_start_command", "pane_current_path", RESUME, DOCUMENT)
        started, skipped = [], []
        for row in rows:
            if not (everything or row["pane_id"] == current) or not (row[RESUME] or row[DOCUMENT]):
                continue
            parked = row["pane_start_command"].rstrip('"').endswith("_park")
            if not (parked or row["pane_current_command"].lstrip("-") in SHELLS):
                skipped.append({"pane": row["pane_id"], "reason": "not at a shell prompt"})
                continue
            provider, _, sid = row[RESUME].partition(" ")
            if row[RESUME] and provider in self.providers and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}", sid):
                argv = [sid if a == "{session_id}" else a for a in self.providers[provider]["argv"]]
            elif row[DOCUMENT]:
                argv = ["nvim", "--", row[DOCUMENT]]
            else:
                skipped.append({"pane": row["pane_id"], "reason": "no usable adapter"})
                continue
            if started and everything:
                time.sleep(delay)
            if parked:
                self.tmux("respawn-pane", "-k", "-t", row["pane_id"], "-c", row["pane_current_path"],
                          self.tmux("show-options", "-gv", "default-shell"), "-ic", shlex.join(argv))
            else:
                self.tmux("send-keys", "-t", row["pane_id"], "-l", shlex.join(argv))
                self.tmux("send-keys", "-t", row["pane_id"], "Enter")
            started.append(row["pane_id"])
        return {"started": started, "skipped": skipped}

    def preflight(self, bundle=None):
        """Before a planned reboot: agents mid-task, editors with unsaved buffers, optional lag evidence."""
        rows = self.panes("session_name", "window_index", "pane_id", "pane_pid", "pane_current_command", *[e["option"] for e in self.providers.values()])
        table = process_table()
        busy, unsaved = [], []
        for row in rows:
            tree = subtree(table, int(row["pane_pid"])) if row["pane_pid"].isdigit() else []
            where = f"{row['session_name']}:{row['window_index']} {row['pane_id']}"
            if any(row[e["option"]] for e in self.providers.values()) and row["pane_current_command"].lstrip("-") not in SHELLS:
                cpu = sum(table[p][1] for p in tree)
                if cpu >= 5.0:  # [INFERRED] ps %cpu over the pane's whole process tree
                    busy.append({"pane": where, "cpu": round(cpu, 1)})
            for document, count in editors(table, tree):
                if count:
                    unsaved.append({"pane": where, "document": document, "unsaved_buffers": count})
        report = {"agents_mid_task": busy, "editors_unsaved": unsaved}
        if bundle:
            Path(bundle).mkdir(parents=True, exist_ok=True, mode=0o700)
            target = Path(bundle) / time.strftime("lag-%Y%m%dT%H%M%S.txt")
            with open(target, "w") as out:
                for title, argv in (("uptime", ["uptime"]), ("memory_pressure", ["memory_pressure", "-Q"]),
                                    ("vm_stat", ["vm_stat"]), ("top by cpu", ["ps", "-Arcwwo", "pid,pcpu,pmem,rss,etime,comm"])):
                    result = subprocess.run(argv, capture_output=True, text=True)
                    body = result.stdout.splitlines()[:26 if argv[0] == "ps" else 40]
                    out.write(f"## {title}\n" + "\n".join(body) + "\n\n")
            target.chmod(0o600)
            report["bundle"] = str(target)
        return report

    def orphans(self):
        """ppid-1 processes born in a pane of this server whose pane no longer exists. Report only."""
        live = {r["pane_id"] for r in self.panes("pane_id")}
        socket = self.tmux("display-message", "-p", "#{socket_path}") if live else ""
        found = []
        out = subprocess.run(["ps", "-Aww", "-E", "-o", "pid=,ppid=,pcpu=,etime=,command="], capture_output=True, text=True).stdout
        for line in out.splitlines():
            parts = line.split(None, 4)
            if len(parts) < 5 or parts[1] != "1":
                continue
            tmux_env, pane = re.findall(r"(?:^|\s)TMUX=(\S+)", parts[4]), re.findall(r"(?:^|\s)TMUX_PANE=(%\d+)", parts[4])
            if tmux_env and pane and tmux_env[-1].split(",")[0] == socket and pane[-1] not in live:
                found.append({"pid": int(parts[0]), "cpu": float(parts[2]), "etime": parts[3], "pane": pane[-1],
                              "command": parts[4].split(" ", 1)[0]})
        return sorted(found, key=lambda o: -o["cpu"])


def main():
    if sys.argv[1:] == ["_park"]:
        print("Topology restored; no program replayed. Press Enter to start the default shell.", flush=True)
        input()
        shell = subprocess.check_output(["tmux", "show-options", "-gv", "default-shell"], text=True).strip()
        os.execv(shell, [shell, "-l"])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", help="tmux -L socket; defaults to current/default server")
    parser.add_argument("--adapters", type=Path)
    parser.add_argument("--output-directory", type=Path, default=Path.home() / ".local/state/tmux-agents-recovery")
    parser.add_argument("--keep-newest", type=int, default=32)
    parser.add_argument("--keep-days", type=int, default=7)
    sub = parser.add_subparsers(dest="command", required=True)
    one = sub.add_parser("checkpoint")
    one.add_argument("--session", required=True)
    sub.add_parser("checkpoint-all")
    restore = sub.add_parser("restore")
    restore.add_argument("file", type=Path)
    restore.add_argument("--apply", action="store_true")
    restore.add_argument("--prefix", default="")
    again = sub.add_parser("resume", help="start recorded agents/editors in idle panes: this pane, or --all staggered")
    again.add_argument("--all", action="store_true")
    again.add_argument("--delay", type=float, default=5.0)
    ahead = sub.add_parser("preflight", help="before a planned reboot: busy agents, unsaved editors")
    ahead.add_argument("--bundle", type=Path, help="also write a small lag-evidence file into this directory")
    sub.add_parser("orphans", help="processes that outlived their tmux pane (report only)")
    args = parser.parse_args()
    try:
        if args.keep_newest < 1 or args.keep_days < 1:
            raise RecoveryError("retention limits must be positive")
        engine = Engine(adapters(args.adapters), args.socket)
        failed = False
        if args.command == "restore":
            result = engine.restore(read_record(args.file)["payload"], args.apply, args.prefix)
            failed = bool(result["failed"])
        elif args.command == "resume":
            result = engine.resume(args.all, args.delay, os.getenv("TMUX_PANE"))
        elif args.command == "preflight":
            result = engine.preflight(args.bundle)
        elif args.command == "orphans":
            result = engine.orphans()
        else:
            name = getattr(args, "session", None)
            payload = engine.capture(name)
            if not payload["sessions"]:
                result = {"changed": False, "reason": "no sessions"}
            else:
                scope = "all" if name is None else "session-" + hashlib.sha256(name.encode()).hexdigest()
                result = save(args.output_directory, scope, payload, args.keep_newest, args.keep_days)
            counts = [len(payload["sessions"]), sum(len(s["windows"]) for s in payload["sessions"]),
                      sum(len(w["panes"]) for s in payload["sessions"] for w in s["windows"])]
            busy = [o for o in engine.orphans() if o["cpu"] >= 25.0] if name is None else []
            args.output_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            log_run(args.output_directory, f"{args.command} sessions={counts[0]} windows={counts[1]} panes={counts[2]} "
                    f"changed={result.get('changed')} warnings={len(engine.warnings)}"
                    + "".join(f" orphan={o['pid']}@{o['cpu']}%" for o in busy)
                    + (" :: " + "; ".join(engine.warnings)[:300] if engine.warnings else ""))
        for warning in engine.warnings:
            print("warning: " + warning, file=sys.stderr)
        print(json.dumps(result, ensure_ascii=False))
        if failed:
            sys.exit(1)
    except RecoveryError as error:
        parser.exit(1, f"recovery failed: {error}; existing and partial sessions are preserved\n")
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        parser.exit(1, f"recovery failed: {type(error).__name__}; existing and partial sessions are preserved\n")


if __name__ == "__main__":
    main()
