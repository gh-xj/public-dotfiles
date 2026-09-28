# macOS Convergence Model

A successful bootstrap must match observable behavior, not only persisted
preferences.

## Discrepancy Loop

When a target Mac differs from the source Mac:

1. Inspect both machines with the narrow command for the affected layer.
2. Identify the durable owner before changing anything.
3. Encode public-safe desired state in that owner.
4. Add a verifier only when evaluation or the owning switch cannot prove the
   result.
5. Apply through the supported bootstrap entrypoint, then inspect behavior and
   run `task check`.

Live one-off commands are probes. If they reveal durable desired state, move
that state into the repo owner instead of keeping an undocumented repair step.

## Owning Layers

| Layer | Owner | Evidence |
| --- | --- | --- |
| Typed macOS defaults | `modules/darwin/defaults.nix` | nix-darwin evaluation and switch |
| Untyped durable preferences | `system.defaults.CustomUserPreferences` in the same module | nix-darwin evaluation and switch |
| Display hardware layout | Host `xj.publicDotfiles.displayLayoutsFile` | `displayplacer list`; no shared physical-panel default |
| Raycast Store extension intent | `config/raycast/extensions.tsv` | `task raycast:install` plus interactive approval |
| App-owned or permission-gated state | the app, macOS, or a downstream private owner | live inspection or human confirmation |

Prefer typed nix-darwin defaults. Use `CustomUserPreferences` for durable keys
that nix-darwin does not type. Add a separate ledger only when no Nix option can
express the state and a dedicated runtime tool must apply it.

Do not restate the same key in a shell verifier or TSV merely to compare it
with `defaults read`. Persisted equality is not behavioral proof, and duplicate
declarations drift.

## Live-State Checks

- Display symptoms: compare `displayplacer list` with
  the host-injected `~/.config/xj/display-layouts.tsv`; see `docs/downstream-composition.md`.
- Trackpad symptoms: compare `modules/darwin/defaults.nix`, persisted defaults,
  and `ioreg -r -c AppleMultitouchDevice`. A logout/login, sleep/wake, or
  reconnect may be required before the device reflects applied preferences.
- Input source symptoms: enabled sources are durable configuration; the
  currently selected source is runtime state.
- Raycast symptoms: preferences may be declared, while Script Command
  registration, aliases, hotkeys, and Store confirmation remain app-owned.

Remote-control software can substitute the client Mac's pointer behavior. When
diagnosing input, confirm the physical target before changing repo policy.

## Interactive Boundaries

TCC grants, GUI-session reloads, encrypted app state, and confirmation-driven
installs do not belong in a blocking repo verifier. Document the manual next
step and keep the public desired state limited to what the repo can actually
own.
