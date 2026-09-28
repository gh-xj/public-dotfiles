#!/usr/bin/env python3
"""Check per-pane launch overrides without running a model or reading auth."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="codex-pane-launch-") as tmp:
    fake = Path(tmp) / "codex"
    fake.write_text("#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
    fake.chmod(0o700)
    env = dict(os.environ, PATH=tmp + ":" + os.environ["PATH"])
    env.pop("TMUX", None)
    env.pop("TMUX_PANE", None)
    def launch(overrides):
        out = subprocess.check_output(["zsh", "-fc", 'source "$1"; codex resume "a task"', "test",
                                       str(repo / ".zsh/codex-tmux.zsh")], env=dict(env, **overrides), text=True)
        return json.loads(out)
    assert launch({}) == ["resume", "a task"]
    assert launch({"TMUX": "/tmp/test,1,0", "TMUX_PANE": "invalid"}) == ["resume", "a task"]
    socket = '/tmp/socket with "quotes"\\and space,123,0'
    args = launch({"TMUX": socket, "TMUX_PANE": "%42"})
    assert args[::2][:3] == ["-c", "-c", "-c"]
    config = tomllib.loads("\n".join(args[1:6:2]))
    assert config["shell_environment_policy"]["set"] == {"TMUX": socket, "TMUX_PANE": "%42"}
    assert config["tui"]["terminal_title"] == []
    assert args[6:] == ["resume", "a task"]
print("Codex launch preserves pane identity, quoting and outside-tmux behavior")
