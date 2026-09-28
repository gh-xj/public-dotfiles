#!/usr/bin/env python3
"""Exercise strict parsing without loading real account state or calling a model."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
if not shutil.which("codex"):
    raise SystemExit("Install the official standalone Codex CLI to validate its seed")
with tempfile.TemporaryDirectory(prefix="codex-strict-") as tmp:
    seed = (repo / "config/codex/config.toml").read_text()
    target = Path(tmp) / "config.toml"
    def run(content):
        target.write_text(content)
        # A subprocess-only runtime home isolates all product state from the user.
        return subprocess.run(["codex", "app-server", "--strict-config"], input="", text=True,
                              env=dict(os.environ, CODEX_HOME=tmp), cwd=tmp,
                              capture_output=True, timeout=30)
    result = run(seed)
    if result.returncode:
        raise SystemExit(result.stderr)
    invalid = run('unsupported_baseline_probe = true\n' + seed)
    assert invalid.returncode != 0 and "unsupported_baseline_probe" in invalid.stderr, "strict parser not exercised"
print("Codex strict config accepted; unknown-key negative control rejected")
