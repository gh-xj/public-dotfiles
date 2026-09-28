#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True

path = Path(__file__).with_name("nvim-health.py")
spec = importlib.util.spec_from_file_location("health", path)
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)
uid = os.getuid()
assert health.candidate(f"123 1 {uid} ?? /bin/nvim /bin/nvim --embed") == 123
for line in [f"123 2 {uid} ?? nvim nvim --embed", f"123 1 {uid} ttys001 nvim nvim --embed",
             f"123 1 {uid} ?? nvim nvim file", f"123 1 {uid+1} ?? nvim nvim --embed",
             f"123 1 {uid} ?? sh sh -c 'nvim --embed'", "invalid"]:
    assert health.candidate(line) is None
result = subprocess.run([sys.executable, str(path), "--kill"], input="", text=True, capture_output=True)
assert result.returncode != 0 and "interactive terminal" in result.stderr
print("nvim-health orphan filters and noninteractive kill refusal passed")
