#!/usr/bin/env python3
"""Full-ledger convergence and failure paths, without live defaults or reloads."""
import copy
import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("settings", Path(__file__).with_name("macos-settings.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.data = m.load(m.DEFAULT_DATA)
        self.live = {d: {k: m.desired_value(k, v) for k, v in keys.items()}
                     for d, keys in self.data["domains"].items()}
        self.calls = []
        self.fail_write = None
        self.fail_reload = None
        self.mock = patch.object(m, "run", side_effect=self.run_command)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def run_command(self, *args, **kwargs):
        self.calls.append(args)
        if args[0] == m.DEFAULTS:
            if args[1] == "export":
                return subprocess.CompletedProcess(args, 0, plistlib.dumps(self.live[args[2]]), b"")
            if args[1] == "write":
                if args[2] == self.fail_write:
                    raise subprocess.CalledProcessError(1, args)
                target = self.live[args[2]]
                if args[4] == "-dict-add":
                    target.setdefault(args[3], {})[args[5]] = plistlib.loads(args[6].encode())
                else:
                    target[args[3]] = plistlib.loads(args[4].encode())
        if args[0] == self.fail_reload:
            return subprocess.CompletedProcess(args, 2, b"", b"permission denied")
        return subprocess.CompletedProcess(args, 0, b"", b"")

    def test_missing_dock_is_not_empty(self):
        for key in ("persistent-apps", "persistent-others"):
            with self.subTest(key=key):
                data = copy.deepcopy(self.data)
                data["domains"]["com.apple.dock"][key] = []
                del self.live["com.apple.dock"][key]
                self.assertTrue(any(row[1] == key for row in m.differences(data)))
                m.command_apply(data, True)
                self.assertEqual(m.differences(data), [])
                self.assertEqual(self.live["com.apple.dock"][key], [])

    def test_partial_write_reloads_and_retry(self):
        self.live["com.apple.dock"].pop("autohide")
        self.live["com.apple.finder"].clear()
        self.fail_write = "com.apple.finder"
        with self.assertRaises(SystemExit):
            m.command_apply(self.data, False)
        self.assertIn(("/usr/bin/killall", "Dock"), self.calls)
        self.fail_write = None
        m.command_apply(self.data, False)
        self.assertEqual(m.differences(self.data), [])

    def test_no_drift_apply_skips_reload(self):
        m.command_apply(self.data, False)
        self.assertFalse(any(c[0] in (m.ACTIVATE_SETTINGS, "/usr/bin/killall") for c in self.calls))

    def test_killall_absent_is_success_other_errors_fail(self):
        def absent(*args, **kwargs):
            return subprocess.CompletedProcess(args, 1 if args[0].endswith("killall") else 0,
                                               b"", b"No matching processes belonging to you were found")
        with patch.object(m, "run", side_effect=absent):
            self.assertEqual(m.reload_domains({"com.apple.dock"}), [])
        self.fail_reload = "/usr/bin/killall"
        self.assertTrue(m.reload_domains({"com.apple.dock"}))

    def test_folder_presentation_and_url_roundtrip(self):
        paths = ["/tmp/A#B", "/tmp/A%20B", "/tmp/A B"]
        expected = [{"folder": p} for p in paths]
        tiles = m.expand_dock("persistent-others", expected)
        tiles[0]["tile-data"].update(arrangement=2, displayas=1, showas=3)
        result = m.expand_dock("persistent-others", list(reversed(expected)), tiles)
        self.assertEqual(m.normalize_dock("persistent-others", result), list(reversed(expected)))
        self.assertEqual({k: result[-1]["tile-data"][k] for k in ("arrangement", "displayas", "showas")},
                         dict(arrangement=2, displayas=1, showas=3))

    def test_capture_atomic_conflict_and_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "settings.json"
            original = json.dumps(self.data).encode()
            path.write_bytes(original)
            with patch.object(m.os, "replace", side_effect=OSError("fault")):
                with self.assertRaises(OSError):
                    m.command_capture(self.data, path)
            self.assertEqual(path.read_bytes(), original)
            original_run = self.run_command
            def concurrent(*args, **kwargs):
                path.write_bytes(original + b"\n")
                return original_run(*args, **kwargs)
            with patch.object(m, "run", side_effect=concurrent):
                with self.assertRaisesRegex(SystemExit, "changed during"):
                    m.command_capture(self.data, path)
            self.assertEqual(path.read_bytes(), original + b"\n")
            self.assertEqual(list(Path(temp).iterdir()), [path])
            m.command_capture(self.data, path)
            self.assertEqual(json.loads(path.read_text()), self.data)

    def test_undeclared_values_and_hotkeys_survive(self):
        domain = "com.apple.symbolichotkeys"
        self.live[domain]["unowned"] = "preserved"
        self.live[domain]["AppleSymbolicHotKeys"]["9999"] = {"enabled": True}
        owned = next(iter(self.data["domains"][domain]["AppleSymbolicHotKeys"]))
        del self.live[domain]["AppleSymbolicHotKeys"][owned]
        m.command_apply(self.data, True)
        self.assertEqual(self.live[domain]["unowned"], "preserved")
        self.assertEqual(self.live[domain]["AppleSymbolicHotKeys"]["9999"], {"enabled": True})
        self.assertEqual(m.differences(self.data), [])

    def test_export_failure_does_not_write(self):
        with patch.object(m, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"permission denied")) as run:
            with self.assertRaises(SystemExit):
                m.command_apply(self.data, False)
            self.assertEqual(run.call_count, 1)
        with patch.object(m, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"Domain does not exist")):
            self.assertEqual(m.domain_values("missing"), {})

    def test_capture_fsync_failure_preserves_source(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "settings.json"
            original = json.dumps(self.data).encode()
            path.write_bytes(original)
            with patch.object(m.os, "fsync", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    m.command_capture(self.data, path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(list(Path(temp).iterdir()), [path])

    def test_invalid_domain_schema(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "settings.json"
            for value in ([], None, {"version": 1, "domains": {"domain": []}}):
                path.write_text(json.dumps(value))
                with self.assertRaises(SystemExit):
                    m.load(path)


if __name__ == "__main__":
    unittest.main()
