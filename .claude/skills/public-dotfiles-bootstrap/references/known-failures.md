# Known Bootstrap Failures

Use this registry before inventing a new fix. The goal is fast routing from a
real target-Mac symptom to the owning harness surface.

| Symptom | Status | First Action | Permanent Owner |
| --- | --- | --- | --- |
| Codex shows `config/batchWrite failed in TUI` after trust prompt | fixed | Restore latest public bootstrap and rerun `task verify:codex-runtime-boundary -- --live` | `fe40b49`; `.codex/config.toml` is a template, live `~/.codex/config.toml` is mutable |
| Tap-to-click still feels disabled even though defaults verification passes | recoverable | Run `task input:reload-live && task input:verify`; inspect global, currentHost, and live `AppleMultitouchDevice` state | `53a1429`, `45d74c1`, `ca9864d`; persisted defaults plus live convergence |
| `defaults read NSGlobalDomain com.apple.mouse.tapBehavior` is not `1` | fixed | Reapply Darwin defaults or run bootstrap apply, then rerun `task input:verify` | `ca9864d`; global tap-to-click key belongs in public input defaults |
| Input verifier fails because the currently selected input source changed | fixed | Remove selected-source comparison from the diagnosis; verify only enabled public-safe sources | `1404b5c`; selected input source is runtime state |
| `task verify:raycast` reports a public-safe preference mismatch | recoverable | Run `task raycast:apply-preferences && task verify:raycast` on the target Mac | `0fe0a2e`; Raycast preferences have a narrow apply task |
| Raycast Store extensions are missing after bootstrap | manual | Run `task raycast:open-extension-installs`, then approve installs in Raycast UI | Store extension install and command hotkey assignment remain interactive |
| Raycast Script Commands or hotkeys are missing | manual | Sync tracked scripts, run `task verify:raycast-scripts`, then register Script Commands and keybindings in Raycast UI | Public repo owns scripts and docs; Raycast owns interactive registration |
| A public CLI such as `gemini` is missing on the target Mac | fixed | Run `./scripts/install-npm-globals.sh && task verify:npm-globals` | `c673eab`; npm-distributed CLIs live in the npm globals ledger |
| Intel macOS 13 bootstrap fails in Nix installer or Homebrew phase | fixed | Use current `scripts/bootstrap-macos.sh`; run `task verify:bootstrap-darwin` before applying | `021368e`, `b4677d8`, `2be583c`, `03bfba8`; platform and OS gates are harness-owned |
| Bootstrap apply passes but the machine still feels off | diagnostic | Run `task dotfiles:converge && task dotfiles:verify`, then inspect the narrow failing layer | `03c30c6`; convergence is a post-apply phase, not an ad hoc checklist |
