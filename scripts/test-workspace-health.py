#!/usr/bin/env python3
"""Boundaries, privacy and read-only native command surface for workspace health."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("control", repo / "scripts/public-control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
assert control.elapsed_seconds("1-02:03:04") == 93784
assert control.elapsed_seconds("10:01") == 601
assert control.elapsed_seconds("00:05") == 5
private = "sensitive-fixture-not-for-output"
calls = []


def runner(argv, **kwargs):
    calls.append(argv)
    if argv[:2] == ["tmux", "list-clients"]:
        out = "xterm-ghostty\nxterm-ghostty\nxterm\n"
    elif argv[:2] == ["tmux", "list-sessions"]:
        out = "$1\n$2\n"
    elif argv[:2] == ["tmux", "list-windows"]:
        out = "@1\n@1\n@2\n"
    elif argv[:2] == ["tmux", "list-panes"]:
        out = "%1\t1\t0\t🤖\n%1\t1\t0\t🤖\n%2\t0\t1\t💬\n%3\t1\t0\t✅\n%4\t0\t0\t" + private + "\n"
    elif argv[0] == "ps" and "pid=,args=" in argv:
        out = f"1 codex\n2 codex app-server\n3 claude\n4 rg {private}\n5 node jest {private}\n6 Ghostty\n7 tmux\n8 {private}\n"
    elif argv[0] == "ps":
        out = ("1 1.0 01:00 /fixture/codex\n2 2.0 01:00 /fixture/codex\n3 3.0 01:00 /fixture/claude/versions/2.0.0\n"
               "4 95.0 20:01 /fixture/rg\n5 80.0 01:00:00 /fixture/node\n6 12.0 01:00 /Applications/Ghostty.app/Contents/MacOS/Ghostty\n"
               "7 8.0 01:00 /fixture/tmux\n8 99.0 20:00 /fixture/" + private + "\n")
    else:
        raise AssertionError("unexpected native operation")
    return subprocess.CompletedProcess([], 0, out, private)


topology = control.tmux_snapshot(runner)
assert topology["clients"] == 3 and topology["ghostty_clients"] == 2
assert topology["sessions"] == 2 and topology["windows"] == 2 and topology["panes"] == 4
assert topology["workmux"]["active"] == 2 and topology["workmux"]["finished"] == 1
assert topology["workmux"]["unknown"] == 1
processes = control.process_snapshot(runner)
thresholds = dict(control.HEALTH_DEFAULTS)
report = control.workspace_report(dict(topology, clients=7, agent_panes=25, panes=41), processes,
                                  {"used_percent": 91, "free_percent": 9}, {"active_matches_desired": False}, thresholds)
assert set(report["warnings"]) == {"attached-client-count", "agent-pane-count", "total-pane-count", "disk-use",
                                   "long-running-high-cpu-workload", "active-generation-drift"}
assert report["provider_cli_processes"] == {"Claude": 1, "Codex": 1}, "shared daemon counted as a CLI agent"
assert report["terminal_cpu_percent"] == {"tmux": 8, "Ghostty": 12}
assert [p["kind"] for p in report["long_running_workloads"]] == ["search", "test"]
encoded = json.dumps(report)
assert private not in encoded and "/fixture" not in encoded and "/Applications" not in encoded
assert all(a[0] in ("ps", "tmux") for a in calls)
assert all(a[0] != "tmux" or a[1].startswith("list-") for a in calls)

boundary = control.workspace_report(dict(topology, clients=6, agent_panes=24, panes=40), [],
                                    {"used_percent": 90}, {"active_matches_desired": True}, thresholds)
assert not boundary["warnings"]
custom = control.workspace_report(topology, [], {"used_percent": 1}, {}, dict(thresholds, clients=2))
assert custom["warnings"] == ["attached-client-count"]
many = [dict(processes[3], pid=i, elapsed_seconds=601, cpu_percent=20) for i in range(12)]
bounded = control.workspace_report(topology, many, {}, {}, dict(thresholds, top=2))
assert len(bounded["long_running_workloads"]) == 2 and bounded["additional_long_running_count"] == 10
unavailable = control.workspace_report({"state": "unavailable"}, None, {}, {}, thresholds)
assert unavailable["provider_cli_processes"] is None and len(unavailable["observation_gaps"]) == 4
invalid = subprocess.run([sys.executable, str(repo / "scripts/public-control.py"), "workspace", "doctor", "--top", "0"], capture_output=True)
assert invalid.returncode != 0
print("workspace counts, thresholds, bounded output, unknown state and private-data suppression verified")
