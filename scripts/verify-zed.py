#!/usr/bin/env python3
"""Validate public Zed JSON and theme colors before Home Manager delivery."""
import json
from pathlib import Path
import re


root = Path(__file__).resolve().parent.parent / ".config/zed"


def colors(value, location):
    if isinstance(value, dict):
        for key, child in value.items():
            colors(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            colors(child, f"{location}[{index}]")
    elif isinstance(value, str) and value.startswith("#"):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", value):
            raise ValueError(f"{location}: expected RGB or RGBA hex color")


for path in sorted(root.rglob("*.json")):
    data = json.loads(path.read_text())
    if path.parent.name == "themes":
        colors(data["themes"], str(path.relative_to(root)))
print("Zed JSON and theme colors verified")
