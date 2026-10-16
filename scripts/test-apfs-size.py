#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile


script = Path(__file__).with_name("apfs-size.py")
spec = importlib.util.spec_from_file_location("apfs_size", script)
apfs_size = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apfs_size)

if sys.platform == "darwin":
    with tempfile.TemporaryDirectory(prefix="apfs-size-") as temporary:
        root = Path(temporary)
        original = root / "original"
        original.write_bytes(b"x" * 16384)
        os.link(original, root / "hardlink")
        allocated, private = apfs_size.tree_size(root)
        assert allocated >= original.stat().st_blocks * 512
        assert private >= apfs_size.private_size(original)
        output = subprocess.run([sys.executable, script, "--bytes", root], check=True, capture_output=True, text=True).stdout
        assert output.splitlines()[0] == "allocated\tprivate\tpath"
        assert output.splitlines()[1].endswith(f"\t{root}")

print("APFS allocated/private sizing and hardlink de-duplication fixtures passed")
