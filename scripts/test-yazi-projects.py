#!/usr/bin/env python3
"""Check Projects persistence through native Yazi and real disposable files."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".config/yazi/plugins/projects.yazi"


def wait_for(predicate, description: str, timeout: float = 5) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {description}")


class Session:
    def __init__(self, base: Path, binary: str, saved: Path):
        self.base = base
        self.notifications = base / "notifications.txt"
        self.events = base / "events.txt"
        config = base / "config"
        shutil.copytree(SOURCE, config / "plugins/projects.yazi")
        main = config / "plugins/projects.yazi/main.lua"
        source = main.read_text().replace("ya.notify(", "test_notify(").replace("ps.pub_to(", "test_publish(")
        # Record the native plugin's notifications and events without altering
        # its filesystem operations or control flow. All values are synthetic.
        main.write_text("""local function record(path, value)
    local f = assert(io.open(path, "a"))
    assert(f:write(value, "\\n"))
    assert(f:close())
end
local function test_notify(message)
    record(os.getenv("PROJECT_TEST_NOTIFICATIONS"), (message.level or "info") .. " " .. message.content:gsub("\\n", " "))
    ya.notify(message)
end
local function test_publish(id, event, value)
    record(os.getenv("PROJECT_TEST_EVENTS"), event)
    ps.pub_to(id, event, value)
end
""" + source)
        (config / "init.lua").write_text("""require("projects"):setup({
    save = { method = "lua", lua_save_path = os.getenv("PROJECT_TEST_PATH") },
})
""")
        (config / "keymap.toml").write_text("""[mgr]
prepend_keymap = [
    { on = "x", run = "plugin projects save" },
    { on = "d", run = "plugin projects delete_all" },
    { on = "l", run = "plugin projects load_last" },
]
""")
        files = base / "files"
        files.mkdir()
        (files / "fixture.txt").write_text("synthetic projects fixture\n")
        self.tmux = ["tmux", "-L", f"yazi-projects-{os.getpid()}-{base.name}"]
        subprocess.run(self.tmux + [
            "-f", "/dev/null", "new-session", "-d", "-s", "probe", "-x", "110", "-y", "32",
            "env", f"YAZI_CONFIG_HOME={config}", f"YAZI_STATE_HOME={base / 'state'}",
            f"YAZI_CACHE_HOME={base / 'cache'}", f"PROJECT_TEST_PATH={saved}",
            f"PROJECT_TEST_NOTIFICATIONS={self.notifications}", f"PROJECT_TEST_EVENTS={self.events}",
            binary, str(files),
        ], check=True, capture_output=True)
        try:
            wait_for(lambda: "fixture.txt" in self.screen(), "native Yazi startup")
        except Exception:
            self.close()
            raise

    def screen(self) -> str:
        return subprocess.check_output(self.tmux + ["capture-pane", "-t", "probe", "-p"], text=True)

    def key(self, key: str) -> None:
        subprocess.run(self.tmux + ["send-keys", "-t", "probe", key], check=True, capture_output=True)

    def save(self) -> None:
        self.key("x")
        wait_for(lambda: "callback" in self.screen(), "save slot chooser")
        self.key("a")
        wait_for(lambda: "Project name:" in self.screen(), "project name input")
        self.key("Enter")
        wait_for(lambda: "Project saved to a" in self.messages(), "successful save notification")

    def messages(self) -> str:
        return self.notifications.read_text() if self.notifications.exists() else ""

    def published(self) -> list[str]:
        return self.events.read_text().splitlines() if self.events.exists() else []

    def quit(self) -> None:
        self.key("q")
        wait_for(lambda: subprocess.run(self.tmux + ["has-session", "-t", "probe"], capture_output=True).returncode != 0,
                 "normal Yazi quit without unfinished tasks", timeout=10)

    def close(self) -> None:
        subprocess.run(self.tmux + ["kill-server"], capture_output=True)


def native_tests(binary: str, fixture: Path) -> None:
    saved = fixture / "quote's parent/missing/projects.json"
    session = Session(fixture / "first", binary, saved)
    try:
        session.save()
        projects = json.loads(saved.read_text())
        assert projects["list"][0]["on"] == "a"
        assert len(projects["list"][0]["project"]["tabs"]) == 1
        assert session.published() == ["project-saved"]
        assert not list(saved.parent.glob("projects.json.tmp-*"))
        session.quit()
    finally:
        session.close()

    session = Session(fixture / "restart", binary, saved)
    try:
        session.key("l")
        wait_for(lambda: "Last project loaded" in session.messages(), "persisted project reload")
        assert session.published() == ["project-loaded"]
        session.key("d")
        wait_for(lambda: "All projects deleted" in session.messages(), "successful delete-all")
        assert json.loads(saved.read_text())["list"] == []
    finally:
        session.close()

    null_tabs = json.loads(json.dumps(projects))
    null_tabs["list"][0]["project"]["tabs"].append(None)
    malformed = ("{broken", "{}", json.dumps({"list": [projects["list"][0], None]}), json.dumps(null_tabs))
    for index, contents in enumerate(malformed):
        saved.write_text(contents)
        session = Session(fixture / f"malformed-{index}", binary, saved)
        try:
            wait_for(lambda: "Invalid JSON or project structure" in session.messages(), "malformed file error")
            initial = len(session.messages().splitlines())
            session.key("x")
            wait_for(lambda: len(session.messages().splitlines()) > initial, "save refusal")
            initial = len(session.messages().splitlines())
            session.key("d")
            wait_for(lambda: len(session.messages().splitlines()) > initial, "delete-all refusal")
            assert saved.read_text() == contents
            assert session.published() == []
            assert "Project saved" not in session.messages()
        finally:
            session.close()

    blocker = fixture / "parent-is-file"
    blocker.write_text("preserve me")
    session = Session(fixture / "blocked", binary, blocker / "projects.json")
    try:
        wait_for(lambda: "Projects file unchanged:" in session.messages(), "file-as-parent error")
        initial = len(session.messages().splitlines())
        session.key("x")
        wait_for(lambda: len(session.messages().splitlines()) > initial, "blocked save refusal")
        assert blocker.read_text() == "preserve me"
        assert session.published() == []
        assert "Project saved" not in session.messages()
    finally:
        session.close()


def main() -> None:
    binary = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else shutil.which("yazi")
    assert binary, "yazi is required"
    assert shutil.which("tmux"), "tmux is required for native Yazi tests"
    lines = subprocess.check_output([binary, "--version"], text=True).splitlines()
    version = next((line.strip() for line in lines if "Version:" in line), lines[0])
    with tempfile.TemporaryDirectory(prefix="yazi-projects-test-") as directory:
        fixture = Path(directory)
        native_tests(binary, fixture)
        # The narrow harness verifies write/close/rename failures with real
        # files; native tests above establish Yazi API/runtime compatibility.
        lua = shutil.which("lua")
        nvim = shutil.which("nvim")
        assert lua or nvim, "lua or nvim is required for persistence fault tests"
        command = [lua] if lua else [nvim, "--headless", "-u", "NONE", "-l"]
        faults = fixture / "faults"
        faults.mkdir()
        subprocess.run(command + [str(ROOT / "scripts/test-yazi-projects.lua"), str(ROOT), str(faults)], check=True)
    print(f"Projects native persistence: {version}; missing parent, restart, corruption and blocked parent passed")


if __name__ == "__main__":
    main()
