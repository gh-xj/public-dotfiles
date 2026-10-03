#!/usr/bin/env python3
"""Enforce small repository harness budgets."""
import argparse
import json
from pathlib import Path
import subprocess


def tracked(repo):
    result = subprocess.run(["git", "-C", str(repo), "ls-files", "-z"], capture_output=True)
    if result.returncode == 0:
        return [Path(item.decode()) for item in result.stdout.split(b"\0") if item]
    return [path.relative_to(repo) for path in repo.rglob("*")
            if (path.is_file() or path.is_symlink()) and ".git" not in path.relative_to(repo).parts]


def line_count(repo, paths):
    total = 0
    for relative in paths:
        try:
            total += len((repo / relative).read_text(errors="replace").splitlines())
        except OSError:
            pass
    return total


def hook_count(repo, paths):
    total = 0
    for relative in paths:
        if relative.suffix != ".json" or "config" not in relative.parts:
            continue
        try:
            value = json.loads((repo / relative).read_text())
        except (OSError, ValueError):
            continue
        stack = [value]
        while stack:
            item = stack.pop()
            if isinstance(item, dict):
                if item.get("type") == "command" and isinstance(item.get("command"), str):
                    total += 1
                stack.extend(item.values())
            elif isinstance(item, list):
                stack.extend(item)
    return total


def skill_count(paths):
    entries = set()
    for relative in paths:
        parts = relative.parts
        for root in ((".agents", "skills"), (".claude", "skills")):
            if len(parts) >= 3 and parts[:2] == root:
                entries.add(parts[:3])
    return len(entries)


def actual(repo, docs_root):
    paths = tracked(repo)
    scripts = [path for path in paths if path.parts[:1] == ("scripts",)]
    docs = [path for path in paths if path.parts[:len(docs_root.parts)] == docs_root.parts]
    listed = subprocess.run(["task", "--dir", str(repo), "--list-all", "--json"],
                            check=True, capture_output=True, text=True)
    tasks = len(json.loads(listed.stdout)["tasks"])
    return {
        "tasks": tasks,
        "script_files": len(scripts),
        "script_loc": line_count(repo, scripts),
        "docs_files": len(docs),
        "docs_loc": line_count(repo, docs),
        "hooks": hook_count(repo, paths),
        "skills": skill_count(paths),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--actual", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    budget_path = repo / "harness-budget.json"
    budget = json.loads(budget_path.read_text())
    observed = actual(repo, Path(budget["docs_root"]))
    if args.actual:
        print(json.dumps(observed, indent=2, sort_keys=True))
        return
    exceeded = {key: (observed[key], budget[key]) for key in observed if observed[key] > budget[key]}
    print("harness budget: " + ", ".join(f"{key}={value}" for key, value in observed.items()))
    if exceeded:
        for key, (value, limit) in exceeded.items():
            print(f"budget exceeded: {key}={value} > {limit}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
