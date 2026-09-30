#!/usr/bin/env python3
"""Exercise delivered Yazi keys, task lifecycle and non-destructive Done moves."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


class Session:
    def __init__(self, binary, root):
        self.root = root
        self.files = root / 'files'
        self.files.mkdir()
        self.config = root / 'config'
        shutil.copytree(ROOT / '.config/yazi', self.config)
        mover = self.config / 'plugins/move-to-done.yazi/main.lua'
        mover.write_text(mover.read_text().replace('local function notify(message, level)', '''local function notify(message, level)
    local f = assert(io.open(os.getenv("YAZI_AUDIT_ROOT") .. "/moves.log", "a"))
    f:write(message, "\\n"); f:close()'''))
        self.env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / 'state'),
                        YAZI_CONFIG_HOME=str(self.config), YAZI_AUDIT_ROOT=str(root),
                        FZF_DEFAULT_OPTS='', FZF_DEFAULT_OPTS_FILE='')
        bins = root / 'bin'
        bins.mkdir()
        for command in ('open', 'nvim', 'qlmanage', 'fzf'):
            script = bins / command
            script.write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, sys, time
r = pathlib.Path(os.environ['YAZI_AUDIT_ROOT'])
with (r / (pathlib.Path(sys.argv[0]).name + '.jsonl')).open('a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
if pathlib.Path(sys.argv[0]).name == 'fzf':
    print('second fixture.txt')
if pathlib.Path(sys.argv[0]).name == 'qlmanage':
    (r / 'quicklook.pid').write_text(str(os.getpid()))
    time.sleep(15)
''')
            script.chmod(0o755)
        self.env['PATH'] = str(bins) + os.pathsep + self.env['PATH']
        probe = self.config / 'plugins/runtime-probe.yazi'
        probe.mkdir()
        (probe / 'main.lua').write_text('''--- @sync entry
return { entry = function()
    local f = assert(io.open(os.getenv("YAZI_AUDIT_ROOT") .. "/snapshot", "w"))
    local h = cx.active.current.hovered
    f:write(tostring(cx.active.current.cwd), "\\n", h and tostring(h.url) or "", "\\n")
    for _, item in ipairs(cx.active.current.files) do
        f:write("\\n", tostring(item.url), "\\t", tostring(item.cha.len))
    end
    f:close()
end }
''')
        keymap = self.config / 'keymap.toml'
        # Keep the production config untouched; insert test-only keys in the first array.
        text = keymap.read_text().replace('prepend_keymap = [', '''prepend_keymap = [
    { on = "<F10>", run = "plugin runtime-probe" },
    { on = "<F12>", run = "shell -- sleep 2" },''', 1)
        keymap.write_text(text)
        self.socket = f'yazi-test-{os.getpid()}-{root.name}'
        self.tmux = ['tmux', '-L', self.socket]
        self.binary = binary

    def start(self):
        # tmux server receives only the isolated environment; no user session is selected.
        subprocess.run(self.tmux + ['-f', '/dev/null', 'new-session', '-d', '-s', 'probe',
                                    '-x', '110', '-y', '32', self.binary, str(self.files)],
                       env=self.env, check=True, capture_output=True)
        self.wait(lambda: 'fixture' in self.capture(), 'Yazi file list')

    def key(self, *keys):
        subprocess.run(self.tmux + ['send-keys', '-t', 'probe', *keys], check=True, capture_output=True)
        time.sleep(.18)

    def capture(self):
        p = subprocess.run(self.tmux + ['capture-pane', '-t', 'probe', '-p'], capture_output=True, text=True)
        log = self.root / 'moves.log'
        return p.stdout + ('\nMove results:\n' + log.read_text() if log.exists() else '')

    def wait(self, condition, what):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.08)
        raise AssertionError(f'Timed out waiting for {what}\n{self.capture()}')

    def snapshot(self):
        snapshot = self.root / 'snapshot'
        snapshot.unlink(missing_ok=True)
        self.key('F10')
        self.wait(lambda: snapshot.exists(), 'manager snapshot')
        return snapshot.read_text().splitlines()

    def hovered(self):
        return self.snapshot()[1]

    def argv(self, command):
        path = self.root / (command + '.jsonl')
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def quit(self):
        self.key('Q')
        self.wait(lambda: subprocess.run(self.tmux + ['has-session', '-t', 'probe'],
                                         capture_output=True).returncode != 0, 'clean quit')

    def close(self):
        subprocess.run(self.tmux + ['kill-server'], capture_output=True)
        pid = self.root / 'quicklook.pid'
        if pid.exists():
            try:
                os.kill(int(pid.read_text()), 15)
            except ProcessLookupError:
                pass


def exercise(binary):
    with tempfile.TemporaryDirectory(prefix='yazi-native-') as temp:
        root = Path(temp)
        s = Session(binary, root)
        fixture = s.files / "fixture quote's file.txt"
        fixture.write_text('fixture\n')
        (s.files / 'second fixture.txt').write_text('second fixture\n')
        try:
            s.start()
            s.key('o', 'p')
            s.wait(lambda: bool(s.argv('open')), 'single open argv')
            assert s.argv('open')[-1] == [str(fixture)]
            s.key('C-a')
            s.key('o', 'p')
            s.wait(lambda: len(s.argv('open')) == 2, 'multi-open argv')
            assert set(s.argv('open')[-1]) == {str(p) for p in s.files.iterdir()}
            s.key('Escape')
            time.sleep(.1)
            s.key('b')
            s.wait(lambda: bool(s.argv('nvim')), 'blocking editor handoff')
            assert s.argv('nvim')[-1] == [str(fixture)]
            s.key('e')
            assert 'Deprecated API' not in s.capture(), 'preview toggle must not warn'
            s.key('e')
            s.key('C-f')
            # Nix's wrapper may put its real fzf ahead of our argv probe.
            s.wait(lambda: bool(s.argv('fzf')) or any(line.lstrip().startswith('>') for line in s.capture().splitlines()), 'fzf launch')
            if not s.argv('fzf'):
                s.key('s', 'e', 'c', 'o', 'n', 'd')
                s.key('Enter')
                s.wait(lambda: any('second fixture.txt' in line and '█' in line for line in s.capture().splitlines()), 'fuzzy target reveal')
            s.key('F10')
            s.wait(lambda: (s.root / 'snapshot').exists(), 'deep search reveal')
            assert (s.root / 'snapshot').read_text().splitlines()[1].endswith('second fixture.txt')
            s.key('g', 'g')
            s.key('F12')
            s.key('w')
            s.wait(lambda: 'Tasks' in s.capture() and 'sleep 2' in s.capture(), 'task panel')
            s.key('Escape')
            time.sleep(2.1)
            s.wait(lambda: s.hovered() == str(fixture), 'first fixture hover')
            s.key('U', 'd')
            s.wait(lambda: (s.files / 'Done' / fixture.name).exists(), 'Done move')
            assert not fixture.exists()
            fixture.write_text('collision fixture\n')
            s.wait(lambda: str(fixture) + '\t18' in s.snapshot(), 'collision entry metadata')
            s.key('g', 'g')
            # Done sorts first; select the original file below it.
            s.key('j')
            s.wait(lambda: s.hovered() == str(fixture), 'collision fixture hover')
            s.key('U', 'd')
            time.sleep(.3)
            assert fixture.read_text() == 'collision fixture\n'
            assert (s.files / 'Done' / fixture.name).read_text() == 'fixture\n'
            s.key('C-p')
            s.wait(lambda: bool(s.argv('qlmanage')), 'orphan Quick Look launch')
            s.quit()
        finally:
            s.close()
    # A selected batch must work for both Url and File selection representations.
    with tempfile.TemporaryDirectory(prefix='yazi-moves-') as temp:
        s = Session(binary, Path(temp))
        names = ["fixture quote's file.txt", 'second fixture.txt']
        for name in names:
            (s.files / name).write_text(name)
        try:
            s.start()
            s.key('C-a')
            s.key('U', 'd')
            s.wait(lambda: all((s.files / 'Done' / n).exists() for n in names), 'selected batch move')
            assert all(not (s.files / n).exists() for n in names)
        finally:
            s.close()
    with tempfile.TemporaryDirectory(prefix='yazi-search-moves-') as temp:
        s = Session(binary, Path(temp))
        names = ['fixture one.txt', 'fixture two.txt']
        for name in names:
            (s.files / name).write_text(name)
        try:
            s.start()
            s.key('s')
            s.wait(lambda: 'Search via fd:' in s.capture(), 'filename search input')
            s.key('f', 'i', 'x', 't', 'u', 'r', 'e')
            s.key('Enter')
            s.wait(lambda: s.hovered().startswith('search://'), 'search result URLs')
            s.key('C-a')
            s.key('U', 'd')
            s.wait(lambda: all((s.files / 'Done' / n).exists() for n in names), 'search result batch move')
            assert all(not (s.files / n).exists() for n in names)
        finally:
            s.close()
    with tempfile.TemporaryDirectory(prefix='yazi-move-link-') as temp:
        s = Session(binary, Path(temp))
        outside = s.root / 'outside'
        outside.mkdir()
        (s.files / 'Done').symlink_to(outside, target_is_directory=True)
        fixture = s.files / 'fixture.txt'
        fixture.write_text('fixture')
        try:
            s.start()
            s.key('C-a')
            s.key('U', 'd')
            s.wait(lambda: 'symbolic link' in s.capture(), 'symlink destination rejection')
            assert fixture.read_text() == 'fixture' and list(outside.iterdir()) == []
        finally:
            s.close()
    print(f'Yazi argv, editor, preview, deep search, tasks, Done batch/collision/symlink and orphan quit passed: {binary}')


if __name__ == '__main__':
    supplied = sys.argv[1:]
    if not supplied:
        supplied = [shutil.which('yazi')]
    for binary in supplied:
        if not binary:
            raise SystemExit('yazi is required')
        path = Path(binary)
        if path.is_dir():
            path = path / 'home-path/bin/yazi'
        exercise(str(path))
