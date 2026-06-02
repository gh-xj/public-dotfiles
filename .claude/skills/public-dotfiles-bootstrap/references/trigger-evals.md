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

### Tap-To-Click Still Broken After Verify

Prior failure: `task input:verify` passed because persisted defaults matched,
but physical tap-to-click on the target Mac still did not behave like the source
Mac.

Expected corrected behavior:

- Inspect `NSGlobalDomain com.apple.mouse.tapBehavior`.
- Inspect currentHost trackpad keys.
- Inspect live `AppleMultitouchDevice` state.
- Run `task input:reload-live` or `task dotfiles:converge` before proposing a
  new baseline change.
- If the remote-control client is being used, confirm the physical target Mac
  behavior before changing repo policy.

Verification:

- `task input:verify`
- On the target Mac when available: `task input:reload-live && task input:verify`

### Selected Input Source Drift

Prior failure: the currently selected input source changed during use and could
be mistaken for public baseline drift.

Expected corrected behavior:

- Do not compare `AppleSelectedInputSources` as a public baseline.
- Keep enabled public-safe input sources in scope.
- Treat the current selected source as runtime state.

Verification:

- `task verify:macos-defaults`

### Missing npm Global CLI

Prior failure: a target Mac missed an npm-distributed CLI such as `gemini`, and
the package could be incorrectly routed to Homebrew cleanup.

Expected corrected behavior:

- Check the npm globals ledger and installer.
- Run `./scripts/install-npm-globals.sh`.
- Verify with `task verify:npm-globals`.
- Do not add npm-distributed CLIs to the Homebrew ledger.

Verification:

- `task verify:npm-globals`

### Raycast Preference Drift

Prior failure: Raycast was installed, but preferences such as customized-command
visibility drifted on the target Mac.

Expected corrected behavior:

- Run `task raycast:apply-preferences`.
- Verify with `task verify:raycast`.
- Do not copy Raycast caches or account/session state into the public repo.

Verification:

- `task raycast:apply-preferences && task verify:raycast`

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
