# Trigger Evals

Use these lightweight cases when editing the skill description or routing
boundaries.

## Should Trigger

| Prompt | Expected Reason |
| --- | --- |
| `mbook trackpad still does not tap-to-click after bootstrap` | target Mac discrepancy after bootstrap |
| `bootstrap a clean Mac from public-dotfiles` | new-machine bootstrap workflow |
| `Raycast settings did not converge on the target Mac` | app preference drift in public baseline |
| `source Mac and target Mac differ in Dock/display/input behavior` | source-vs-target convergence audit |
| `which macOS settings should become repo-owned harness?` | public/private and layer ownership decision |

## Should Not Trigger

| Prompt | Better Owner |
| --- | --- |
| `remove an unused npm package from my config` | `config-manager`, unless part of bootstrap drift |
| `edit my Neovim keymap` | `config-manager` |
| `clean private-config secrets` | private repo workflow / security-specific guidance |
| `write a generic Nix module` | ordinary Nix/code workflow |
| `design a new Claude/Codex skill` | `skill-builder` |

## Regression Cases

### Worker Mac Intel Ventura Darwin Apply

Prior failure: The worker Mac bootstrap surfaced several config-harness gaps:
Intel host platform detection, Nix installer version compatibility on macOS 13,
Homebrew Tier 2/Tier 3 source-build and cask version gates, npm CLI ledger
ownership, live trackpad reload lag, and Raycast preference drift.

Expected corrected behavior:

- `bootstrap-macos.sh` detects `x86_64-darwin` and Intel Homebrew prefix.
- Intel macOS 13 uses a Nix installer that runs on the target OS.
- npm-distributed CLIs stay out of the Homebrew ledger.
- Homebrew casks are gated by target macOS major version.
- Bootstrap apply can continue after persisted input defaults are written even
  when live trackpad state needs a later reload.
- Post-bootstrap convergence is explicit: `task dotfiles:converge`, then
  `task dotfiles:verify`.

Verification:

- `task verify:bootstrap-darwin`
- `task dotfiles:verify`
- On the target Mac when available: `task dotfiles:converge && task dotfiles:verify`
