# configctl Control Plane Migration Plan

Status: active
Date: 2026-05-17
Owner repo: `public-dotfiles`
Related design: `docs/configctl-design.md`

## Goal

Make `configctl` the single deterministic CLI surface for machine
configuration while preserving public/private repo ownership, fast verification,
and existing user-facing compatibility during migration.

The end state is:

- app, agent, workspace, package, home, status, verify, and release workflows
  are reached through `configctl`
- Taskfiles are thin aliases and composition only
- legacy scripts and templates are deleted after CLI parity, except for
  intentionally retained exact-path shims
- private behavior is driven by private manifests and overlays, not private Go
  code
- every mutating command emits a durable redacted operation report by default

## Current State

Already present:

- `tools/configctl` Go CLI with Kong command structure
- common result envelope and diagnostics under `internal/report`
- `app typewhisper` vertical slice
- `home status`, `home resolve`, `home plan`, `home apply`, and `home verify`
- root Taskfile aliases for install and configctl verification

Known missing surfaces:

- root `configctl status`
- root `configctl verify --profile default|full`
- repo registry and private overlay loading beyond existing home manifest paths
- operation report persistence under `.configctl/runs/`
- release capture and release apply flow
- workspace manifest and `workspace` commands
- agent skills and Codex auth commands
- package audit commands
- app validators for terminal, nvim, lazygit, karabiner, Ghostty, and tmux

## Design Decisions

1. `configctl` is the only real operator surface. Taskfiles and temporary
   wrappers delegate to it.
2. Build the root `status` and `verify` spine before migrating more leaves.
3. Default `verify` is a fast required gate. `--profile full` owns slower or
   optional checks.
4. Go owns orchestration, typed parsing, diagnostics, and redaction. Shell is
   allowed only for real external tools such as `nvim`, `ghostty`, `tmux`,
   `karabiner_cli`, `gitleaks`, `skillset`, and `gh`.
5. After parity, delete legacy scripts, docs, and templates aggressively.
   Retain only exact-path shims required by external callers.
6. One public-safe binary serves both repos. Private behavior comes from
   private manifests, repo registry overlays, and invocation context.
7. Manifests and native ledgers are source of truth. Taskfiles and scripts are
   never policy sources.
8. Broad reconciliation uses `plan` and `apply`. Narrow mutation uses
   `--dry-run`. `status` and `verify` never mutate.
9. Package handling is audit and verify only in v1. No install, remove, or
   upgrade commands.
10. Secrets and auth surfaces report presence, shape, mode, owner, and
    redacted status only. They never print values.
11. `configctl agent skills` wraps the external `skillset` CLI for now.
12. Codex auth snapshot behavior is preserved, but validation, output safety,
    and backup assumptions are tightened.
13. Workspaces use a generic `workspaces.toml`; migrate only `oss` first.
14. Default `verify` skips optional workspace availability. Full verify fails
    for required workspace invariants.
15. App validators are leaf checks plus `app terminal verify` as a composite.
16. Manifest/source drift fails closed. No auto-delete.
17. `configctl` may own a constrained audited release flow, but not general Git
    porcelain.
18. Cross-repo release is allowed only as separate per-repo commits with one
    run report.
19. Release staging is operation-report and path scoped, not broad dirty-tree
    scoped.
20. Mutating commands write durable redacted operation reports by default.
21. Operation reports live under ignored `.configctl/runs/` in the invoking repo
    with `--report-out` for explicit redirection.
22. Release requires a release-eligible operation report.
23. Manual edits enter release through explicit `release capture`.
24. Use a small public `configctl/repos.toml` registry plus a private overlay
    for full local paths.
25. Manifests avoid arbitrary environment expansion. Use relative paths and
    explicit absolutes only where the domain requires them.
26. Do not add a primary `doctor` command. `task doctor` may alias
    `configctl verify --profile full`.
27. Keep `install.sh` only briefly as a `configctl home apply` shim, then
    delete it when references are gone.
28. Preserve `--copy` for compatibility and bootstrap. Symlink remains the
    ownership model.
29. Copied overrides do not count as repo ownership unless the manifest declares
    `mode = "copy"`.
30. Add targeted runtime cleanup later if needed. No broad auto-prune and no
    cleanup inside `verify`.
31. Keep `app` for installed app config workflows. Use separate domains for
    local tools and automation.
32. Refactor internals into strict layers before adding the next domains.
33. Operation reports have stable schema versions.
34. Release accepts same-major operation reports only and fails closed
    otherwise.
35. Reports store sanitized args plus redaction metadata.
36. Release recomputes current verification requirements and records the actual
    commands run.
37. Verification profiles start in Go, with room for a later `verify.toml`.
38. Verification runs sequentially in v1 with stable ordered output.
39. `verify` collects all safe failures and exits nonzero if any required check
    fails.
40. `status` includes read-only Git dirty state, summarized.

## Non-Goals

- no `configctl` command for reset, rebase, amend, force-push, broad `git add`,
  checkout, or raw Git porcelain
- no package install, remove, or upgrade in v1
- no hidden mutation from `status`, `verify`, `audit`, or `validate`
- no auto-delete of manifest entries, source files, live config, or runtime
  state
- no secret value printing and no `--show-secrets`
- no broad runtime prune
- no private-only Go implementation path

## Architecture Target

Refactor toward these layers before broad migration:

```text
cmd/                 Kong command declarations and thin orchestration
internal/app/        root runtime, output, profile selection, command registry
internal/domain/     typed domain logic with no direct process or Git calls
internal/adapters/   filesystem, process, git, OS, clock, and TOML/JSON I/O
internal/report/     output envelope, operation reports, redaction metadata
internal/verify/     check registry, profiles, ordered execution
pkg/version/         build metadata
```

Contracts:

- `cmd` packages parse flags, call one domain operation, and emit one envelope.
- domain packages return typed results and diagnostics, not formatted strings.
- adapters isolate side effects and make tests deterministic.
- report writing is centralized and redacted by default.
- release logic consumes operation reports, not ad hoc shell history.

## Milestone 1: Architecture Foundation

Operation boundary: reshape `configctl` internals without adding new behavior.

- [x] introduce root runtime package for shared command options and execution
- [x] move common emit/fail helpers out of `cmd`
- [x] define operation report schema version, report path policy, sanitized args,
      and redaction metadata
- [x] add adapter interfaces for filesystem, process execution, Git inspection,
      clock, and repo root discovery
- [x] add public `configctl/repos.toml` with public-safe repo names and relative
      path defaults
- [x] add private overlay loading hook without requiring the private repo
- [x] preserve current command behavior and JSON envelope
- [x] add tests for report path selection, repo registry loading, and redaction

Verification:

- `task configctl:verify`
- `task dotfiles:verify`
- `task secrets:staged`

## Milestone 2: Root Status and Verify Spine

Operation boundary: add read-only root inspection and verification contracts.

- [x] add `configctl status`
- [x] add `configctl verify --profile default|full`
- [x] implement sequential stable check execution
- [x] collect all safe failures before exiting nonzero
- [x] make root status summarize managed repos, Git dirty counts, manifests,
      check counts, and high-level drift
- [x] make default verify fast and required-only
- [x] map `task doctor` to `configctl verify --profile full` if retained
- [x] keep existing Taskfile verify aliases as thin wrappers

Verification:

- `tools/configctl/bin/configctl --json status`
- `tools/configctl/bin/configctl --json verify`
- `tools/configctl/bin/configctl --json verify --profile full`
- `task dotfiles:verify`

## Milestone 3: Operation Reports

Operation boundary: make mutating commands leave durable audited run records.

- [ ] create `.configctl/runs/` as ignored generated state in invoking repos
- [ ] add `--report-out` global or mutation-scoped option
- [ ] write reports for `home apply` and TypeWhisper import first
- [ ] include schema version, command, sanitized args, repo roots, touched paths,
      backups, verification hints, diagnostics, and redaction metadata
- [ ] mark reports as release-eligible only when the command can be safely
      replayed into a commit boundary
- [ ] avoid report writes for read-only commands unless explicitly requested

Verification:

- `configctl home apply --dry-run --report-out <tmpfile>`
- `configctl app typewhisper import --dry-run --report-out <tmpfile>`
- JSON schema and redaction unit tests

## Milestone 4: Workspace Domain

Operation boundary: migrate external workspace links into typed manifest logic.

- [ ] add `configctl/workspaces.toml`
- [ ] define `oss` with local path, external path, symlink mode, and required
      profile behavior
- [ ] implement `workspace status`
- [ ] implement `workspace verify [name]`
- [ ] implement `workspace link <name> --dry-run`
- [ ] make `link` refuse to overwrite real directories
- [ ] make optional external absence a warning in default verify
- [ ] remove or wrap the legacy workspace script after command parity

Verification:

- `configctl --json workspace status`
- `configctl --json workspace verify oss`
- `configctl --json workspace link oss --dry-run`
- `configctl --json verify`
- `configctl --json verify --profile full`

## Milestone 5: Agent Domain

Operation boundary: migrate agent topology without changing source ownership.

- [ ] implement `agent status`
- [ ] implement `agent verify`
- [ ] implement `agent policy status`
- [ ] implement `agent policy verify`
- [ ] implement `agent skills list|verify|sync --dry-run`
- [ ] call `skillset` as an external tool behind a process adapter
- [ ] implement `agent codex-auth status|save|use`
- [ ] validate Codex auth JSON before save/use
- [ ] always back up current auth before switching snapshots
- [ ] remove hardcoded dated backup assumptions
- [ ] redact every token-adjacent value from human and JSON output
- [ ] move old Taskfile/script logic to wrappers or delete it after parity

Verification:

- `configctl --json agent status`
- `configctl --json agent verify`
- `configctl --json agent skills verify`
- `configctl --json agent codex-auth status`
- `task dotfiles:verify`
- `task secrets:staged`

## Milestone 6: App Validators

Operation boundary: move deterministic app checks under `configctl app`.

- [ ] implement `app nvim verify`
- [ ] implement `app lazygit verify`
- [ ] implement `app ghostty verify`
- [ ] implement `app tmux verify`
- [ ] implement `app karabiner verify`
- [ ] implement `app terminal verify` as the composite terminal workflow check
- [ ] keep app-specific external tools behind process adapters
- [ ] replace Taskfile shell blocks with thin aliases

Verification:

- `configctl --json app nvim verify`
- `configctl --json app lazygit verify`
- `configctl --json app ghostty verify`
- `configctl --json app tmux verify`
- `configctl --json app karabiner verify`
- `configctl --json app terminal verify`
- `task dotfiles:verify`

## Milestone 7: Package Audit

Operation boundary: add package ledger inspection without install mutation.

- [ ] inspect public and private `Brewfile`
- [ ] inspect public and private `npm-globals.txt`
- [ ] inspect installed Homebrew formulae and casks
- [ ] inspect installed global npm packages
- [ ] report tracked-missing, installed-untracked, duplicated, and config-without
      package-ledger support
- [ ] include package checks in full verify when external tools are available
- [ ] avoid network freshness checks by default

Verification:

- `configctl --json package status`
- `configctl --json package audit`
- `configctl --json package verify`
- `configctl --json verify --profile full`

## Milestone 8: Release Flow

Operation boundary: add constrained commit orchestration from operation reports.

- [ ] implement `release capture` for manual edits with explicit paths
- [ ] implement release eligibility checks for operation reports
- [ ] recompute current verification requirements before staging
- [ ] stage only operation-report or capture-declared paths
- [ ] support cross-repo release as separate commits with one run report
- [ ] inspect cached diff before commit
- [ ] record repo, commit hash, branch, staged files, and verification commands
- [ ] refuse same-major report incompatibility failures closed
- [ ] avoid push by default unless the command explicitly owns push semantics

Verification:

- dry-run release capture on docs-only paths
- release unit tests for path scoping and report schema compatibility
- `task dotfiles:verify`
- `task secrets:staged`

## Milestone 9: Cleanup and Compatibility Removal

Operation boundary: delete legacy policy surfaces once every caller has moved.

- [ ] inventory scripts, Taskfile shell blocks, docs, and templates that still
      mention legacy commands
- [ ] replace docs with `configctl` commands before deleting wrappers
- [ ] keep exact-path shims only when an external caller still needs them
- [ ] delete `install.sh` after it is only a `configctl home apply` shim and
      references are gone
- [ ] delete obsolete skillsctl/codex-auth/workspace shell logic after parity
- [ ] keep Taskfile aliases minimal and documented

Verification:

- `rg` for deleted command names
- `task dotfiles:verify`
- `task secrets:staged`

## Cross-Repo Policy

- public-safe config and the `configctl` binary live in `public-dotfiles`
- private account, machine-local, and token-adjacent manifests live in
  `private-config`
- source files are edited in the owning repo, never through live `$HOME`
  symlinks
- each repo gets separate commits and pushes
- every Git operation starts with `git status --short`
- staging uses explicit paths only
- any final report with uncommitted changes must name the reason

## Next Action

Start Milestone 3 by writing durable redacted operation reports for mutating
commands, beginning with `home apply` and TypeWhisper import.
