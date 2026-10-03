#!/usr/bin/env python3
"""Exercise macos-settings against an isolated throwaway defaults domain."""

import json
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


repo = Path(__file__).resolve().parent.parent
tool = repo / "scripts/macos-settings.py"
domain = "io.xj.settings-test." + uuid.uuid4().hex


def call(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, env=environment)


def write(key, value):
    xml = plistlib.dumps(value, fmt=plistlib.FMT_XML).decode()
    call("/usr/bin/defaults", "write", domain, key, xml)


with tempfile.TemporaryDirectory() as temp:
    environment = os.environ | {"HOME": temp, "CFFIXED_USER_HOME": temp}
    data_path = Path(temp) / "settings.json"
    data = {
        "version": 1,
        "domains": {
            domain: {
                "AppleSymbolicHotKeys": {"28": {"enabled": False}},
                "NSUserKeyEquivalents": {"Close Tab": "@w"},
                "array": [1, "two", True],
                "boolean": True,
                "dictionary": {"count": 3, "enabled": False},
                "floating": 0.5,
                "integer": 7,
            }
        },
    }
    data_path.write_text(json.dumps(data), encoding="utf-8")
    try:
        write("undeclared", "preserved")
        write("AppleSymbolicHotKeys", {"99": {"enabled": True}})
        applied = call(sys.executable, str(tool), "--data", str(data_path), "apply", "--no-reload")
        assert "changed domains:" in applied.stdout
        live = plistlib.loads(call("/usr/bin/defaults", "export", domain, "-").stdout.encode())
        assert live["undeclared"] == "preserved"
        assert live["AppleSymbolicHotKeys"]["28"] == {"enabled": False}
        assert live["AppleSymbolicHotKeys"]["99"] == {"enabled": True}
        assert live["boolean"] is True and live["integer"] == 7 and live["floating"] == 0.5
        assert live["array"] == [1, "two", True]
        assert live["NSUserKeyEquivalents"] == {"Close Tab": "@w"}
        call(sys.executable, str(tool), "--data", str(data_path), "diff")
        write("integer", 8)
        assert call(sys.executable, str(tool), "--data", str(data_path), "diff", check=False).returncode == 1
        call(sys.executable, str(tool), "--data", str(data_path), "capture")
        captured = json.loads(data_path.read_text(encoding="utf-8"))
        declared = captured["domains"][domain]
        assert declared["integer"] == 8
        assert "undeclared" not in declared
        assert "99" not in declared["AppleSymbolicHotKeys"]
    finally:
        call("/usr/bin/defaults", "delete", domain, check=False)

print("macos settings tests passed")
