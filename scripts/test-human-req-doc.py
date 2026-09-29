"""Exercise request-document naming against an isolated tmux server."""

import os
from pathlib import Path
import subprocess
import tempfile


repo = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="request-document-") as temporary:
        root = Path(temporary).resolve()
        socket = str(root / "tmux.sock")
        clean_env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")}
        clean_env.update(HOME=str(root), EDITOR="/usr/bin/true")

        def tmux(*args):
            return subprocess.check_output(
                ["tmux", "-S", socket, *args], env=clean_env, text=True
            ).strip()

        def field(pane, name):
            return tmux("display-message", "-p", "-t", pane, "#{" + name + "}")

        def create(env, directory=root):
            subprocess.run(
                ["task", "--taskfile", str(repo / "global/Taskfile.yml"),
                 "new-human-req-doc", "--", "--name", "Human Request"],
                cwd=directory, env=env, check=True, capture_output=True, text=True,
            )

        try:
            pane = tmux("-f", "/dev/null", "new-session", "-d", "-P", "-F", "#{pane_id}",
                        "-s", "workspace", "-n", "original", "-c", str(root), "sleep 120")
            tmux("set-option", "-w", "-t", pane, "automatic-rename", "off")
            sibling = tmux("split-window", "-d", "-P", "-F", "#{pane_id}", "-t", pane, "sleep 120")
            other = tmux("new-window", "-P", "-F", "#{pane_id}", "-t", "workspace:",
                         "-n", "unrelated", "sleep 120")
            tmux("set-option", "-w", "-t", other, "automatic-rename", "off")
            tmux("select-window", "-t", other)
            tmux("select-pane", "-t", pane, "-T", "agent identity")
            env = dict(clean_env, TMUX=f"{socket},{field(pane, 'pid')},0", TMUX_PANE=pane)
            create(env)
            document = Path(field(pane, "@recovery_document"))
            assert document.parent == root / ".docs/human-requests"
            assert document.read_text() == "# Human Request\n"
            assert field(pane, "window_name") == "Human-Request"
            assert field(sibling, "@recovery_document") == ""
            assert field(other, "window_name") == "unrelated"
            assert field(other, "@recovery_document") == ""
            assert field(pane, "session_name") == "workspace"
            assert field(pane, "pane_title") == "agent identity"
            create(env)
            second = Path(field(pane, "@recovery_document"))
            assert second == document.with_name(document.stem + "-2.md")
            assert second.is_file() and document.is_file()
            outside = root / "outside"
            outside.mkdir()
            create(clean_env, outside)
            documents = list((outside / ".docs/human-requests").glob("*.md"))
            assert len(documents) == 1
            assert documents[0].read_text() == "# Human Request\n"
            assert field(pane, "@recovery_document") == str(second)
        finally:
            subprocess.run(["tmux", "-S", socket, "kill-server"], env=clean_env, capture_output=True)
    print("request-document window naming, pane metadata, suffixes, and outside-tmux behavior passed")


if __name__ == "__main__":
    main()
