#!/usr/bin/env python3
"""Resolve the example's declarative repo paths against the checkout under test."""
import os
from pathlib import Path
import sys

generated, repo = map(Path, sys.argv[1:])
example = Path("/Users/example/public-dotfiles")


def resolve(path, seen=()):
    if path in seen:
        raise AssertionError(f"link cycle: {path}")
    if path.is_relative_to(example):
        path = repo / path.relative_to(example)
    if path.is_symlink():
        dest = Path(os.readlink(path))
        return resolve(dest if dest.is_absolute() else path.parent / dest, (*seen, path))
    assert path.exists(), f"dangling generated target: {path}"
    return path


def visit(path, ancestors=()):
    target = resolve(path)
    if target.is_dir():
        assert target not in ancestors, f"directory cycle: {path}"
        for child in target.iterdir():
            visit(child, (*ancestors, target))


visit(generated)
print("all generated symlinks resolve (example repo paths mapped to checkout)")
