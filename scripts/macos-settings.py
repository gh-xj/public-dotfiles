#!/usr/bin/env python3
import argparse
import json
import os
import plistlib
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse


DEFAULT_DATA = Path(__file__).resolve().parent.parent / "config/macos/settings.json"
DEFAULTS = "/usr/bin/defaults"
ACTIVATE_SETTINGS = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
RESTARTS = {
    "NSGlobalDomain": ("SystemUIServer",),
    "com.apple.WindowManager": ("SystemUIServer",),
    "com.apple.dock": ("Dock",), "com.apple.finder": ("Finder",),
    "com.apple.symbolichotkeys": ("SystemUIServer",),
}


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True)


def load(path):
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("version") != 1 or not isinstance(data.get("domains"), dict):
        raise SystemExit(f"invalid settings data: {path}")
    return data


def domain_values(domain):
    result = run(DEFAULTS, "export", domain, "-", check=False)
    if result.returncode:
        return {}
    return plistlib.loads(result.stdout)


def portable_path(value):
    home = str(Path.home())
    return "~" + value[len(home) :] if value == home or value.startswith(home + "/") else value


def expand(value):
    if isinstance(value, str) and (value == "~" or value.startswith("~/")):
        return os.path.expanduser(value)
    if isinstance(value, list):
        return [expand(item) for item in value]
    if isinstance(value, dict):
        return {key: expand(item) for key, item in value.items()}
    return value


def dock_url(tile):
    raw = tile.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
    if raw.startswith("file:"):
        raw = unquote(urlparse(raw).path)
    return portable_path(raw.rstrip("/"))


def normalize_dock(key, value):
    result = []
    for tile in value:
        kind = tile.get("tile-type")
        if "spacer-tile" in (kind or ""):
            result.append({"spacer": "small" if kind == "small-spacer-tile" else "regular"})
        elif key == "persistent-apps":
            result.append({"app": dock_url(tile)})
        else:
            result.append({"folder" if kind == "directory-tile" else "file": dock_url(tile)})
    return result


def expand_dock(key, value):
    result = []
    for item in value:
        if "spacer" in item:
            kind = "small-spacer-tile" if item["spacer"] == "small" else "spacer-tile"
            result.append({"tile-data": {}, "tile-type": kind})
            continue
        label, path = next(iter(item.items()))
        path = os.path.expanduser(path)
        if key == "persistent-apps" and label == "app":
            result.append({"tile-data": {"file-data": {"_CFURLString": path, "_CFURLStringType": 0}}})
        else:
            tile_data = {"file-data": {"_CFURLString": "file://" + path, "_CFURLStringType": 15}}
            if label == "folder":
                tile_data.update({"arrangement": 1, "displayas": 0, "showas": 0})
            result.append({"tile-data": tile_data, "tile-type": "directory-tile" if label == "folder" else "file-tile"})
    return result


def normalized(key, value):
    if key in ("persistent-apps", "persistent-others"):
        return normalize_dock(key, value)
    return value


def desired_value(key, value):
    if key in ("persistent-apps", "persistent-others"):
        return expand_dock(key, value)
    return expand(value)


def write_value(domain, key, value):
    xml = plistlib.dumps(value, fmt=plistlib.FMT_XML).decode()
    run(DEFAULTS, "write", domain, key, xml)


def differences(data):
    drift = []
    for domain, declared in data["domains"].items():
        live = domain_values(domain)
        for key, expected in declared.items():
            if key == "AppleSymbolicHotKeys":
                actual_ids = live.get(key, {})
                for hotkey_id, wanted in expected.items():
                    actual = actual_ids.get(hotkey_id, "<missing>")
                    if actual != expand(wanted):
                        drift.append((domain, f"{key}.{hotkey_id}", wanted, actual))
            else:
                actual = normalized(key, live.get(key, "<missing>"))
                if actual != expected:
                    drift.append((domain, key, expected, actual))
    return drift


def command_diff(data):
    drift = differences(data)
    for domain, key, expected, actual in drift:
        print(f"{domain}:{key}")
        print("  declared=" + json.dumps(expected, ensure_ascii=False, sort_keys=True))
        print("  live=" + json.dumps(actual, ensure_ascii=False, sort_keys=True))
    print(f"{len(drift)} setting(s) differ")
    return bool(drift)


def command_capture(data, path):
    missing = []
    for domain, declared in data["domains"].items():
        live = domain_values(domain)
        for key in list(declared):
            if key == "AppleSymbolicHotKeys":
                actual_ids = live.get(key, {})
                for hotkey_id in list(declared[key]):
                    if hotkey_id in actual_ids:
                        declared[key][hotkey_id] = actual_ids[hotkey_id]
                    else:
                        missing.append(f"{domain}:{key}.{hotkey_id}")
            elif key in live:
                declared[key] = normalized(key, live[key])
            else:
                missing.append(f"{domain}:{key}")
    if missing:
        raise SystemExit("missing live settings: " + ", ".join(missing))
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"captured {sum(len(keys) for keys in data['domains'].values())} declared keys")


def command_apply(data, no_reload):
    changed = set()
    for domain, key, expected, _actual in differences(data):
        if key.startswith("AppleSymbolicHotKeys."):
            hotkey_id = key.rsplit(".", 1)[1]
            xml = plistlib.dumps(expand(expected), fmt=plistlib.FMT_XML).decode()
            run(DEFAULTS, "write", domain, "AppleSymbolicHotKeys", "-dict-add", hotkey_id, xml)
        else:
            write_value(domain, key, desired_value(key, expected))
        changed.add(domain)
    if changed and not no_reload:
        run(ACTIVATE_SETTINGS, "-u", check=False)
        for service in sorted({item for domain in changed for item in RESTARTS.get(domain, ())}):
            run("/usr/bin/killall", service, check=False)
    print("changed domains: " + (", ".join(sorted(changed)) if changed else "none"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    commands = parser.add_subparsers(dest="command", required=True)
    apply_parser = commands.add_parser("apply")
    apply_parser.add_argument("--no-reload", action="store_true", help=argparse.SUPPRESS)
    commands.add_parser("capture")
    commands.add_parser("diff")
    args = parser.parse_args()
    data = load(args.data)
    if args.command == "apply":
        command_apply(data, args.no_reload)
    elif args.command == "capture":
        command_capture(data, args.data)
    else:
        raise SystemExit(command_diff(data))


if __name__ == "__main__":
    main()
