#!/usr/bin/env python3
import argparse
import copy
import tempfile
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
    if (not isinstance(data, dict) or data.get("version") != 1
            or not isinstance(data.get("domains"), dict)
            or any(not isinstance(keys, dict) for keys in data["domains"].values())):
        raise SystemExit(f"invalid settings data: {path}")
    return data


def domain_values(domain):
    result = run(DEFAULTS, "export", domain, "-", check=False)
    if result.returncode:
        if b"does not exist" in result.stderr:
            return {}
        raise subprocess.CalledProcessError(result.returncode, (DEFAULTS, "export", domain, "-"),
                                            result.stdout, result.stderr)
    values = plistlib.loads(result.stdout)
    if not isinstance(values, dict):
        raise ValueError(f"invalid defaults domain: {domain}")
    return values


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


def expand_dock(key, value, live=()):
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
            tile_data = {"file-data": {"_CFURLString": Path(path).as_uri(), "_CFURLStringType": 15}}
            if label == "folder":
                tile_data.update({"arrangement": 1, "displayas": 0, "showas": 0})
                for old in live:
                    if old.get("tile-type") == "directory-tile" and dock_url(old) == portable_path(path.rstrip("/")):
                        tile_data.update({field: old["tile-data"][field] for field in
                                          ("arrangement", "displayas", "showas") if field in old["tile-data"]})
                        break
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
                actual = normalized(key, live[key]) if key in live else "<missing>"
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
    source = path.read_bytes()
    if json.loads(source) != data:
        raise SystemExit("settings changed since load; retry capture")
    data = copy.deepcopy(data)
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
    payload = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".settings-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, path.stat().st_mode & 0o777)
        if path.read_bytes() != source:
            raise SystemExit("settings changed during capture; retry capture")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f"captured {sum(len(keys) for keys in data['domains'].values())} declared keys")


def reload_domains(domains):
    failures = []
    commands = [(ACTIVATE_SETTINGS, "-u")] + [
        ("/usr/bin/killall", service) for service in
        sorted({item for domain in domains for item in RESTARTS.get(domain, ())})]
    for command in commands:
        try:
            result = run(*command, check=False)
            absent = (command[0] == "/usr/bin/killall" and result.returncode == 1
                      and b"No matching processes" in result.stderr)
            if result.returncode and not absent:
                failures.append(f"{command[0]} {command[1]} (exit {result.returncode})")
            else:
                print(f"reload {command[1]}: " + ("not running" if absent else "ok"))
        except OSError as error:
            failures.append(f"{command[0]}: {error}")
    return failures


def command_apply(data, no_reload):
    changed = set()
    write_error = None
    try:
        for domain, key, expected, _actual in differences(data):
            if key.startswith("AppleSymbolicHotKeys."):
                hotkey_id = key.rsplit(".", 1)[1]
                xml = plistlib.dumps(expand(expected), fmt=plistlib.FMT_XML).decode()
                run(DEFAULTS, "write", domain, "AppleSymbolicHotKeys", "-dict-add", hotkey_id, xml)
            else:
                value = desired_value(key, expected)
                if key in ("persistent-apps", "persistent-others"):
                    value = expand_dock(key, expected, domain_values(domain).get(key, []))
                write_value(domain, key, value)
            changed.add(domain)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        write_error = error
    # Reconcile caches even with no drift: a previous reload may have failed.
    domains = changed if write_error else set(data["domains"])
    failures = reload_domains(domains) if domains and not no_reload else []
    print("changed domains: " + (", ".join(sorted(changed)) if changed else "none"))
    if no_reload:
        print("reload skipped (--no-reload)")
    if write_error or failures:
        raise SystemExit("apply incomplete; retry apply: " + "; ".join(
            ([str(write_error)] if write_error else []) + failures))


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
