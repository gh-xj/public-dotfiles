# macOS Convergence Model

`public-dotfiles` restores a comfortable public-safe macOS setup by converging
multiple preference and runtime layers. A passing bootstrap should mean the
target Mac behaves like the source Mac, not only that a plist contains expected
values.

## Discrepancy Loop

When the target Mac differs from the source Mac:

1. Inspect both machines with `defaults read` for the affected domain, or the
   narrow command for the reported area.
2. Identify the owning layer for the behavior.
3. Encode desired state in `modules/darwin/defaults.nix`, or in a ledger when
   no Nix option expresses it.
4. Add a verifier only when the switch cannot already prove the outcome.
   Restating a Nix declaration in shell buys nothing and rots.
5. Apply through `./scripts/bootstrap-macos.sh --darwin --apply` or the narrow
   task, then re-run the verifier.

Live one-off commands are only acceptable as probes. If they reveal desired
behavior, fold the result back into the repo harness.

## Layers

| Layer | Owned By | Example | Verification |
| --- | --- | --- | --- |
| nix-darwin typed defaults | `modules/darwin/defaults.nix` | Dock, Finder, keyboard repeat, typed trackpad keys | the switch itself |
| Custom user defaults | `system.defaults.CustomUserPreferences` | Raycast preferences, input source arrays, ByHost trackpad keys | the switch itself |
| Live hardware/runtime state | `config/macos/display-layouts.tsv` | display arrangement, which no Nix option expresses | `displayplacer` via `task display:apply` |
| App runtime state | public ledgers plus manual install flows | Raycast Store extensions | `task verify:raycast-extensions` |

## Placement Decision

When adding a new macOS-related setting, pick the narrowest owning layer that
can actually converge the behavior.

1. Use nix-darwin typed defaults when the setting is already modeled by
   `system.defaults` and no runtime/session caveat is known.
2. Use `CustomUserPreferences` when the key is still a durable persisted
   preference, but nix-darwin does not expose it as a typed option.
3. Use the TSV-ledger plus script path when the setting is ByHost/currentHost,
   input-specific, or otherwise needs a shell-level apply/verify loop.
4. Add a live-state verifier when persisted values are known to produce false
   positives without a GUI-session or hardware-state check.
5. Treat app-encrypted, TCC-gated, confirmation-driven, or UI-registered state
   as an interactive boundary. Record the durable public intent in a ledger or
   doc, but do not pretend the runtime state is repo-owned.

Anti-rules:

- Do not add a shell ledger when `system.defaults` already expresses the same
  setting cleanly.
- Do not keep the same setting in both `modules/darwin/defaults.nix` and a TSV
  ledger unless the persisted key and the live-state check genuinely target
  different layers.
- Do not treat `defaults read` as sufficient proof when the symptom is
  behavioral and a known live-state check exists.

## Live-State Rule

Any macOS setting with an observable runtime behavior should have a live-state
check when a reliable one exists. A persisted preference check alone can be a
false positive.

Known live checks:

| Behavior | Persisted State | Live Check |
| --- | --- | --- |
| Display resolution and layout | `config/macos/display-layouts.tsv` | `displayplacer list` via `task display:apply` |
| Trackpad tap, thresholds, and three-finger gestures | `modules/darwin/defaults.nix` | applied by the switch; no separate live check |

When a live check cannot be made deterministic because of TCC, GUI-session, or
human-confirmation requirements, keep it out of the blocking gate and provide a
task that fails with a concrete manual next step.

## Interactive Boundaries

Some state cannot be restored silently from an SSH-only bootstrap:

| Surface | Reason | Current Task |
| --- | --- | --- |
| Raycast Script Command directory and command hotkeys | Raycast stores registration, aliases, and hotkeys in app-managed/encrypted runtime state | `task raycast:open-script-setup`, then user confirms commands appear in Raycast search |
| Raycast Store extensions | Raycast owns Store install confirmation and extension runtime state | `task raycast:open-extension-installs`, then `task verify:raycast-extensions` |
| Trackpad live reload | WindowServer may keep stale `AppleMultitouchDevice` preferences until a GUI reload or logout/login | logout/login on the target Mac |

The repo should make these boundaries explicit. A bootstrap can be excellent
without pretending macOS permission prompts and app-owned confirmation flows are
fully automatable.
