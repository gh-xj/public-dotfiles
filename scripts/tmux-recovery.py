#!/usr/bin/env python3
"""Versioned topology recovery. No scrollback, foreground commands or runtime DB reads."""
import argparse
import fcntl
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
        if not re.fullmatch(r"@[a-z][a-z0-9_]*", option) or option in options or option in (DOCUMENT, "@agent_label") or option.startswith("@workmux"):
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


def _validate_payload(payload):
    sessions = payload["sessions"]
    if not isinstance(sessions, list) or not 1 <= len(sessions) <= 256:
        raise RecoveryError("invalid session count")
    targets = set()
    for session in sessions:
        name = text(session["name"], 255)
        if not name or "." in name or ":" in name or name in targets:
            raise RecoveryError("invalid or duplicate target session name")
        targets.add(name)
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
                cwd = Path(text(pane["cwd"]))
                if not cwd.is_absolute():
                    raise RecoveryError("checkpoint working directory is missing")
                text(pane["title"]); text(pane["label"])
                if not isinstance(pane["providers"], dict):
                    raise RecoveryError("invalid providers")
                for provider, identity in pane["providers"].items():
                    text(provider, 32); text(identity["option"])
                    session_id(identity["session_id"])
                if pane.get("document"):
                    doc = Path(text(pane["document"]))
                    if not doc.is_absolute():
                        raise RecoveryError("invalid or missing document path")


def validate_payload(payload):
    try:
        _validate_payload(payload)
    except (KeyError, TypeError, AttributeError) as error:
        raise RecoveryError("invalid checkpoint payload structure") from error


class Engine:
    def __init__(self, provider_map, socket=None):
        self.providers = provider_map
        self.command = ["tmux"] + (["-L", socket] if socket else [])

    def tmux(self, *args):
        result = subprocess.run([*self.command, *map(str, args)], capture_output=True, text=True)
        if result.returncode:
            raise RecoveryError("tmux operation failed; any newly created sessions are left for inspection")
        return result.stdout.rstrip("\n")

    def field(self, target, name):
        return self.tmux("display-message", "-p", "-t", target, "#{" + name + "}")

    def exists(self, name):
        return subprocess.run([*self.command, "has-session", "-t", "=" + name], capture_output=True).returncode == 0

    def capture(self, name=None):
        if name is None:
            result = subprocess.run([*self.command, "list-sessions", "-F", "#{session_id}"], capture_output=True, text=True)
            if result.returncode:
                if "no server running" in result.stderr or "No such file or directory" in result.stderr:
                    return {"sessions": []}
                raise RecoveryError("cannot enumerate tmux sessions")
            ids = result.stdout.splitlines()
        else:
            ids = [self.field("=" + name + ":", "session_id")]
        sessions = []
        for sid in ids:
            session = {"name": self.field(sid, "session_name"), "windows": []}
            active_window = self.field(sid, "window_id")
            for wid in self.tmux("list-windows", "-t", sid, "-F", "#{window_id}").splitlines():
                window = {"name": self.field(wid, "window_name"), "index": int(self.field(wid, "window_index")),
                          "layout": self.field(wid, "window_layout"), "width": int(self.field(wid, "window_width")),
                          "height": int(self.field(wid, "window_height")), "active": wid == active_window, "panes": []}
                active_pane = self.field(wid, "pane_id")
                pane_ids = self.tmux("list-panes", "-t", wid, "-F", "#{pane_id}").splitlines()
                for pid in pane_ids:
                    pane = {"index": int(self.field(pid, "pane_index")), "cwd": self.field(pid, "pane_current_path"),
                            "title": self.field(pid, "pane_title"), "label": self.field(pid, "@agent_label"),
                            "active": pid == active_pane, "providers": {}}
                    for provider, entry in self.providers.items():
                        value = self.field(pid, entry["option"])
                        if value:
                            pane["providers"][provider] = {"option": entry["option"], "session_id": session_id(value)}
                    document = self.field(pid, DOCUMENT)
                    if document:
                        pane["document"] = document
                    window["panes"].append(pane)
                window["panes"].sort(key=lambda p: p["index"])
                window["layout"] = self.field(wid, "window_layout")
                layout_ids = re.findall(r"\d+x\d+,\d+,\d+,(\d+)", window["layout"])
                if set(layout_ids) != {p[1:] for p in pane_ids} or active_pane not in pane_ids:
                    raise RecoveryError("topology changed during capture; retry")
                dimensions = re.match(r"^[0-9a-f]+,(\d+)x(\d+),", window["layout"])
                window["width"], window["height"] = map(int, dimensions.groups())
                session["windows"].append(window)
            session["windows"].sort(key=lambda w: w["index"])
            if sum(w["active"] for w in session["windows"]) != 1 or len({w["index"] for w in session["windows"]}) != len(session["windows"]):
                raise RecoveryError("window topology changed during capture; retry")
            sessions.append(session)
        if len({s["name"] for s in sessions}) != len(sessions):
            raise RecoveryError("session names changed during capture; retry")
        return {"sessions": sorted(sessions, key=lambda s: s["name"])}

    def validate(self, payload, prefix="", resume_agents=False, resume_documents=False):
        validate_payload(payload)
        for session in payload["sessions"]:
            name = text(prefix + session["name"], 255)
            if "." in name or ":" in name or self.exists(name):
                raise RecoveryError("invalid or existing target session; choose --prefix or inspect it manually")
            for window in session["windows"]:
                for pane in window["panes"]:
                    if not Path(pane["cwd"]).is_dir():
                        raise RecoveryError("checkpoint working directory is missing")
                    for provider, identity in pane["providers"].items():
                        if provider not in self.providers or self.providers[provider]["option"] != identity["option"]:
                            raise RecoveryError("checkpoint requires a matching trusted adapter map")
                    if resume_agents and len(pane["providers"]) > 1:
                        raise RecoveryError("multiple provider IDs in one pane; select the intended identity first")
                    if pane.get("document") and resume_documents:
                        if not Path(pane["document"]).is_file():
                            raise RecoveryError("invalid or missing document path")
                        if resume_agents and pane["providers"]:
                            raise RecoveryError("agent and document resume conflict in one pane; choose one resume mode")

    def restore(self, payload, apply=False, prefix="", resume_agents=False, resume_documents=False):
        self.validate(payload, prefix, resume_agents, resume_documents)
        plan = {"mode": "apply" if apply else "plan", "sessions": [prefix + s["name"] for s in payload["sessions"]],
                "windows": sum(len(s["windows"]) for s in payload["sessions"]),
                "panes": sum(len(w["panes"]) for s in payload["sessions"] for w in s["windows"]),
                "resume_agents": resume_agents, "resume_documents": resume_documents}
        if not apply:
            return plan
        parked = [sys.executable, str(Path(__file__).resolve()), "_park"]
        resumes = []
        for session in payload["sessions"]:
            name = prefix + session["name"]
            first = session["windows"][0]
            pid = self.tmux("new-session", "-d", "-s", name, "-n", first["name"], "-c", first["panes"][0]["cwd"],
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
                                    "-c", window["panes"][0]["cwd"], "-P", "-F", "#{pane_id}", *parked)
                wid = self.field(pid, "window_id")
                self.tmux("set-option", "-w", "-t", wid, "automatic-rename", "off")
                self.tmux("set-option", "-w", "-t", wid, "remain-on-exit", "on")
                self.tmux("set-option", "-w", "-t", wid, "pane-base-index", window["panes"][0]["index"])
                self.tmux("resize-window", "-t", wid, "-x", window["width"], "-y", window["height"])
                active_pane = pid
                for pindex, pane in enumerate(window["panes"]):
                    if pindex:
                        pid = self.tmux("split-window", "-d", "-h", "-t", pid, "-c", pane["cwd"], "-P", "-F", "#{pane_id}", *parked)
                        self.tmux("select-layout", "-t", wid, "tiled")
                    self.tmux("select-pane", "-t", pid, "-T", pane["title"])
                    self.tmux("set-option", "-p", "-t", pid, "@agent_label", pane["label"])
                    for provider, identity in pane["providers"].items():
                        self.tmux("set-option", "-p", "-t", pid, identity["option"], identity["session_id"])
                        if resume_agents:
                            resumes.append((pid, pane["cwd"], [identity["session_id"] if a == "{session_id}" else a for a in self.providers[provider]["argv"]]))
                    if pane.get("document"):
                        self.tmux("set-option", "-p", "-t", pid, DOCUMENT, pane["document"])
                        if resume_documents:
                            resumes.append((pid, pane["cwd"], ["nvim", "--", pane["document"]]))
                    if pane["active"]:
                        active_pane = pid
                self.tmux("select-layout", "-t", wid, window["layout"])
                self.tmux("select-pane", "-t", active_pane)
                if window["active"]:
                    active_window = wid
            self.tmux("select-window", "-t", active_window)
        # Only our new parked processes are replaced. No attach/switch-client,
        # no captured commands, and no destructive rollback on partial failure.
        for pid, cwd, argv in resumes:
            shell = self.tmux("show-options", "-gv", "default-shell")
            self.tmux("respawn-pane", "-k", "-t", pid, "-c", cwd, shell, "-ic", shlex.join(argv))
        return plan


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
    restore.add_argument("--resume-agents", action="store_true")
    restore.add_argument("--resume-documents", action="store_true")
    args = parser.parse_args()
    try:
        if args.keep_newest < 1 or args.keep_days < 1:
            raise RecoveryError("retention limits must be positive")
        engine = Engine(adapters(args.adapters), args.socket)
        if args.command == "restore":
            result = engine.restore(read_record(args.file)["payload"], args.apply, args.prefix, args.resume_agents, args.resume_documents)
        else:
            name = getattr(args, "session", None)
            payload = engine.capture(name)
            if not payload["sessions"]:
                result = {"changed": False, "reason": "no sessions"}
            else:
                scope = "all" if name is None else "session-" + hashlib.sha256(name.encode()).hexdigest()
                result = save(args.output_directory, scope, payload, args.keep_newest, args.keep_days)
        print(json.dumps(result, ensure_ascii=False))
    except RecoveryError as error:
        parser.exit(1, f"recovery failed: {error}; existing and partial sessions are preserved\n")
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        parser.exit(1, f"recovery failed: {type(error).__name__}; existing and partial sessions are preserved\n")


if __name__ == "__main__":
    main()
