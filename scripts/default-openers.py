#!/usr/bin/env python3
"""Apply and inspect public file-opening preferences through LaunchServices."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


INVENTORY = "md markdown mdown mkd mkdn mdx pdf txt rtf json yaml toml py sh html jpg png heic svg mp4 mov mp3 wav zip docx xlsx pptx epub csv".split()


def read_policy(path):
    mappings = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        fields = line.split("#", 1)[0].split()
        if not fields:
            continue
        if (len(fields) != 3 or fields[2] != "all"
                or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", fields[0])
                or not re.fullmatch(r"\.[a-z0-9]+", fields[1])):
            raise ValueError(f"{path}:{number}: expected bundle_id .extension all")
        bundle, extension, _ = fields
        extension = extension[1:]
        if extension in mappings:
            raise ValueError(f"{path}:{number}: duplicate extension .{extension}")
        mappings[extension] = bundle
    if not mappings:
        raise ValueError(f"{path}: empty policy")
    return mappings


def run(args):
    return subprocess.run(args, text=True, capture_output=True, check=False)


def installed_apps(bundles):
    # NSWorkspace resolves registered applications by ID without launching them.
    script = '''ObjC.import("AppKit"); JSON.stringify(%s.map(function(id) {
        var url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(id);
        return [id, url ? ObjC.unwrap(url.path) : null];
    }));''' % json.dumps(sorted(set(bundles)))
    result = run(["/usr/bin/osascript", "-l", "JavaScript", "-e", script])
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return dict(json.loads(result.stdout))


def current_app(duti, extension):
    result = run([duti, "-x", extension])
    lines = result.stdout.splitlines()
    if result.returncode or len(lines) != 3:
        return "(no default)", None
    return lines[0], lines[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["list", "plan", "apply", "check", "validate"], default="list", nargs="?")
    parser.add_argument("--policy", type=Path, default=Path(__file__).resolve().parent.parent / "config/macos/default-openers.duti")
    parser.add_argument("--skip-missing", action="store_true", help="apply available apps and warn about missing ones (bootstrap only)")
    args = parser.parse_args()
    if args.skip_missing and args.action != "apply":
        parser.error("--skip-missing is only valid with apply")
    mappings = read_policy(args.policy)
    if args.action == "validate":
        print(f"default opener policy valid: {len(mappings)} extensions")
        return 0
    if sys.platform != "darwin":
        raise RuntimeError("default openers require macOS")
    if args.action == "apply" and os.geteuid() == 0:
        raise RuntimeError("run as the logged-in user, without sudo")
    duti = shutil.which("duti")
    if not duti:
        raise RuntimeError("duti is missing; install the public Home Manager profile")
    apps = installed_apps(mappings.values())
    missing = sorted(bundle for bundle, path in apps.items() if not path or not Path(path).is_dir())
    if args.action == "apply" and missing and not args.skip_missing:
        raise RuntimeError("missing applications: " + ", ".join(missing))
    failures = 0
    if args.action == "apply":
        # Register document types before resolving extensions on a fresh install.
        registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for bundle, path in apps.items():
            if bundle not in missing:
                result = run([registrar, "-f", path])
                if result.returncode:
                    raise RuntimeError(f"register {bundle}: {result.stderr.strip()}")
        for extension, desired in mappings.items():
            if desired in missing:
                continue
            result = run([duti, "-s", desired, "." + extension, "all"])
            if result.returncode:
                print(f"ERROR .{extension}: {result.stderr.strip()}", file=sys.stderr)
                failures += 1
    extensions = list(dict.fromkeys([*mappings, *INVENTORY])) if args.action == "list" else mappings
    deadline = time.monotonic() + 30
    for extension in extensions:
        desired = mappings.get(extension)
        name, current = current_app(duti, extension)
        # LS setters return before other processes see the updated association.
        if args.action == "apply" and desired not in missing:
            while (not current or current.casefold() != desired.casefold()) and time.monotonic() < deadline:
                time.sleep(0.25)
                name, current = current_app(duti, extension)
        if desired is None:
            status = "unmanaged"
        elif desired in missing:
            status = "MISSING APP"
            if not (args.action == "apply" and args.skip_missing):
                failures += 1
        elif current and current.casefold() == desired.casefold():
            status = "OK"
        else:
            status = "DRIFT"
            failures += 1
        print(f".{extension:9} {name:25} {current or '-':42} {status}" + (f" -> {desired}" if desired else ""))
    return int(failures > 0) if args.action in ["apply", "check"] else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"default-openers: {error}", file=sys.stderr)
        sys.exit(1)
