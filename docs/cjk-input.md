# CJK input with modal editors

Terminal programs with a Vim mode (Claude Code `editorMode: "vim"`, Neovim,
zsh vi-mode) only receive text after the input method commits it. They cannot
see whether a Chinese IME is active or composing. Two failures follow:

- Leaving INSERT with a CJK source active sends NORMAL-mode keys such as
  `hjkl`, `dd`, and `w` into the composition box.
- Esc during composition is consumed by the IME, so the editor never sees the
  mode change.

Application-level remaps cannot fix hardware events that the IME consumes.
These rules therefore live in Karabiner, before the input method.

## Rules

The rules are declared in `.config/karabiner/karabiner.json` and mirrored in
`.config/karabiner/assets/complex_modifications/xjm-rules.json`:

| Key | Action |
| --- | --- |
| `j`+`k` together (30 ms window) | Esc, then select U.S. |
| `Ctrl+[` in Ghostty | `Ctrl+[`, then select U.S. |
| Tap left Shift | Select U.S. |
| Tap right Shift | Select Shuangpin |

Each Shift key selects a fixed source rather than toggling, so repeated taps
cannot drift. The source IDs are `com.apple.keylayout.US` and the personal
default `com.apple.inputmethod.SCIM.Shuangpin`; change the latter in both files
if another CJK source is preferred.

## Invariants

- End every `to_if_alone` that selects an input source with a key event.
  Karabiner did not fire a `to_if_alone` made only of non-key events. Append
  `{ "key_code": "vk_none" }`.
- Select sources absolutely; never invoke the system previous-source toggle.
  Direct TIS selection measured about 8 ms median, while the shortcut took
  hundreds of milliseconds and reached 2.6 seconds under load. During that
  delay guards may still observe the old source.
- macOS can intermittently show the CJK menu icon while typing remains English,
  especially under memory pressure. A focus change (`Cmd-Tab` away and back)
  restores it. Do not add a per-keystroke process workaround.
- Simple modifications run before complex ones. Physical Esc is remapped to
  grave here, so a complex `from: escape` rule would take over the backtick.
- Never run a process per keystroke. Endpoint security can make process startup
  visibly laggy; `im-select` startup measured from 0.06 to 9.8 seconds.
- Do not switch sources from a Claude Code status line. Its mode updates are
  debounced and can be cancelled by later updates.

## Debugging

- Synthetic keystrokes can bypass Karabiner. Validate with the physical keys.
- Inspect the current source in Karabiner-EventViewer.
- Before saving, run
  `karabiner_cli --lint-complex-modifications .config/karabiner/assets/complex_modifications/xjm-rules.json`.
- A successful reload appears as `core_configuration is updated` in
  `~/.local/share/karabiner/log/console_user_server.log`.
- Temporary timing logs must be removed after diagnosis; never retain a
  per-keypress `shell_command`.

## Neovim

`formatoptions` includes `m` and `B`. This lets `gq` break CJK prose between
multibyte characters and makes `J` join CJK lines without an inserted space.
No IME-switching plugin is installed: Karabiner owns mode-exit switching.

To write a long Chinese prompt in Claude Code, press `Ctrl+G` and edit it in
`$EDITOR`.

## Optional cursor indicator override

macOS may display an input-source indicator beside the cursor on each switch.
Changing the system-wide UIKit feature flag requires sudo and a reboot, so it
is intentionally outside `task apply`. Treat any such override as a separate,
human-approved machine operation.

## Validation

After changing the rules, run `task check`, then test by hand:

1. With Shuangpin active, tap left Shift repeatedly; U.S. stays selected.
2. Tap right Shift and type pinyin immediately; candidates appear.
3. In a Vim-mode terminal editor, commit Chinese text and press `jk`; NORMAL
   mode starts with U.S. selected.
4. Type words containing `jk` and `kj`; an unintended Esc must not fire.
