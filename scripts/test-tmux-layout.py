#!/usr/bin/env python3
"""纯 layout 兼容测试，不运行 tmux 或读取用户状态。"""
import json
from pathlib import Path
import runpy
import unittest

api = runpy.run_path(str(Path(__file__).with_name("tmux-recovery.py")))
convert = api["legacy_layout"]
RecoveryError = api["RecoveryError"]


def pane(identity, index=0, width=80, height=24, x=0, y=0):
    return dict(t="p", w=width, h=height, x=x, y=y, i=index, I="%" + str(identity))


class LayoutCompatibility(unittest.TestCase):
    def test_legacy_is_unchanged(self):
        value = "b25c,80x24,0,0,0"
        self.assertEqual(convert(value), value)

    def test_v2_single_pane_retains_geometry_and_identity(self):
        result = convert(json.dumps(dict(V=2, L={**pane(17), "a": True, "l": 0})))
        self.assertEqual(result.split(",", 1)[1], "80x24,0,0,17")
        self.assertRegex(result[:4], r"^[0-9a-f]{4}$")

    def test_nested_horizontal_vertical(self):
        tree = dict(t="h", w=120, h=50, x=0, y=0, c=[
            pane(4, width=60, height=50),
            dict(t="v", w=59, h=50, x=61, y=0, c=[
                pane(8, 1, 59, 25, 61, 0), pane(12, 2, 59, 24, 61, 26)])])
        result = convert(json.dumps(dict(V=2, L=tree)))
        self.assertEqual(result.split(",", 1)[1],
                         "120x50,0,0{60x50,0,0,4,59x50,61,0[59x25,61,0,8,59x24,61,26,12]}")

    def test_bad_version_and_duplicate_keys_fail(self):
        for value in ('{"V":3,"L":{}}', '{"V":true,"L":{}}', '{"V":2,"V":2,"L":{}}', '{broken'):
            with self.subTest(value=value), self.assertRaises(RecoveryError):
                convert(value)

    def test_invalid_leaf_types_and_fields_fail(self):
        for replacement in ({"w": True}, {"h": 0}, {"x": -1}, {"I": "%1;command"},
                            {"i": True}, {"a": "true"}, {"l": "bad"}, {"unknown": "field"}, {"t": "z"}):
            with self.subTest(replacement=replacement), self.assertRaises(RecoveryError):
                convert(json.dumps(dict(V=2, L={**pane(1), **replacement})))
        missing = pane(1)
        del missing["I"]
        with self.assertRaises(RecoveryError):
            convert(json.dumps(dict(V=2, L=missing)))

    def test_duplicate_pane_ids_and_empty_split_fail(self):
        for children in ([], [pane(1)], [pane(1), pane(1, 1)]):
            with self.subTest(children=children), self.assertRaises(RecoveryError):
                convert(json.dumps(dict(V=2, L=dict(t="h", w=80, h=24, x=0, y=0, c=children))))

    def test_deep_and_oversized_layout_fail(self):
        tree = pane(1)
        for i in range(34):
            tree = dict(t="h", w=80, h=24, x=0, y=0, c=[pane(i + 2), tree])
        with self.assertRaises(RecoveryError):
            convert(json.dumps(dict(V=2, L=tree)))
        with self.assertRaises(RecoveryError):
            convert("{" + " " * 131072 + "}")


if __name__ == "__main__":
    unittest.main()
