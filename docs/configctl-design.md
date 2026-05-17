# configctl Design

Status: proposed
Work item: W-0004

## Purpose

`configctl` is the deterministic control-plane CLI for xj's machine
configuration. It should give agents and humans one stable command surface for
repo-backed config operations while leaving judgment and policy routing in the
`config-manager` skill.

The intended split is:

```text
config-manager skill -> intent, policy, ownership judgment
configctl            -> deterministic inspect, plan, verify, import, sync
Taskfile.yml         -> thin compatibility aliases
repo files           -> source of truth
```

`public-dotfiles` owns the public-safe `configctl` implementation so the public
repo can bootstrap on its own when the private overlay is absent. `private-config`
remains a full-machine entrypoint through its private manifests and wrappers.

## Non-Goals

`configctl` must not become a second agent brain or an automatic repo janitor.
These behaviors are out of scope:

- deciding whether a new config belongs in public or private without agent/user
  judgment
- committing, pushing, rebasing, or otherwise mutating git history
- printing secret values or token contents
- broad destructive cleanup without explicit target, plan, and later design
- replacing app-specific knowledge notes that are not mechanically checkable
- driving remote login flows or network freshness checks by default

## Implementation

Create a new Go CLI:

```text
tools/configctl/
```

Implementation choices:

- Use Kong for the command tree.
- Keep command structs declarative and typed.
- Use a shared result envelope for human and JSON output.
- Put domain logic behind typed packages with tests.
- Keep filesystem, SQLite, process, git, and command execution behind small
  adapters.
- Prefer structured parsers over string scraping where practical.

Recommended layout:

```text
tools/configctl/
  cmd/
  internal/app/
  internal/domain/
    typewhisper/
    home/
    agent/
    packageledger/
    workspace/
  internal/adapters/
    filesystem/
    git/
    process/
    sqlite/
  internal/report/
  pkg/version/
```

## Command Tree

Use a surface-first namespace model. Top-level namespaces describe machine
surfaces, not implementation mechanisms.

```text
configctl status
configctl verify

configctl home status
configctl home resolve <path>
configctl home plan [--public-only] [--private-repo <path>] [--mode symlink|copy]
configctl home apply [--public-only] [--private-repo <path>] [--mode symlink|copy]
configctl home verify [--all]

configctl app typewhisper validate
configctl app typewhisper status
configctl app typewhisper import [--dry-run] [--allow-running]
configctl app typewhisper export --output <path>
configctl app terminal verify
configctl app nvim verify
configctl app lazygit verify
configctl app karabiner verify

configctl agent status
configctl agent verify
configctl agent sync [--dry-run]
configctl agent policy status
configctl agent policy verify
configctl agent skills list
configctl agent skills verify
configctl agent skills sync [--dry-run]
configctl agent codex-auth status
configctl agent codex-auth save api|chatgpt
configctl agent codex-auth use api|chatgpt

configctl package status
configctl package audit
configctl package verify

configctl workspace status
configctl workspace verify [<name>]
configctl workspace link <name> [--dry-run]

configctl storage audit
configctl storage plan
```

Rejected top-level namespaces:

- `install`
- `ownership`
- `symlinks`
- `doctor`

Those are mechanisms or legacy vocabulary. They belong under `home` or as
Taskfile compatibility aliases.

## Status and Verify

`status` and `verify` are distinct contracts.

`configctl status`:

- read-only
- summarizes current state
- exits `0` if inspection completes
- may report warnings and drift
- does not act as a gate

`configctl verify`:

- read-only
- exits nonzero when invariants fail
- default profile is fast and stable
- optional profiles may include slower or environment-dependent checks

Potential profiles:

```text
configctl verify
configctl verify --profile bootstrap
configctl verify --profile full
configctl verify --include optional-workspaces
```

Default verification should not fail because an optional external volume is not
mounted, network state is unavailable, or a GUI setup step cannot be checked
mechanically.

## Output Contract

Every command should support `--json`. JSON uses a common envelope:

```json
{
  "schema_version": "configctl.v1",
  "command": "app.typewhisper.import",
  "ok": true,
  "changed": true,
  "dry_run": false,
  "summary": "imported TypeWhisper lexicon",
  "data": {},
  "diagnostics": []
}
```

Fields:

- `schema_version`: stable output schema version
- `command`: dotted command name
- `ok`: semantic command success
- `changed`: whether live or repo state changed
- `dry_run`: whether mutation was suppressed
- `summary`: short human-readable summary
- `data`: typed command-specific payload
- `diagnostics`: structured warnings and errors

Diagnostics should use stable codes:

```json
{
  "severity": "warning",
  "code": "workspace.external_missing",
  "message": "oss external path is missing; volume may not be mounted",
  "path": "/Volumes/xj-daily/dev/oss"
}
```

Exit codes:

```text
0 success
1 runtime or semantic failure
2 usage error
```

## Redaction

All output is redact-by-default, including JSON.

Rules:

- Never print contents of auth snapshots, `.npmrc`, `.ssh/*`, tokens, plugin
  registries, API keys, or provider secrets.
- Report presence, validity, owner, path, mtime, and mode when useful.
- Do not add `--show-secrets`.
- `--json` output should be safe to paste into an agent conversation.

Example:

```json
{
  "path": "/Users/xj/private-config/.codex/auth.json",
  "exists": true,
  "valid_json": true,
  "redacted": true
}
```

## Mutation Model

Use a strict safety model:

```text
read-only: validate, status, export, resolve, audit, verify
plan:      home plan, storage plan
apply:     home apply, import, sync, link, codex-auth use/save
```

Mutation vocabulary:

- Use `plan/apply` when reconciling a broad surface.
- Use `--dry-run` when previewing one named operation.

Examples:

```text
configctl home plan
configctl home apply
configctl app typewhisper import --dry-run
configctl app typewhisper import
configctl workspace link oss --dry-run
configctl workspace link oss
```

All apply-capable operations should report planned actions, touched paths, and
backups created.

## Manifests

`configctl` should keep declarative manifests in visible repo-root directories:

```text
public-dotfiles/configctl/
private-config/configctl/
```

Generated state does not belong there.

### Home Manifests

Use split manifests:

```text
~/public-dotfiles/configctl/home.toml
~/private-config/configctl/home.toml
```

Rules:

- The public manifest lists public entries only.
- The private manifest lists private overlay entries only.
- Running from `public-dotfiles` loads the public manifest and an optional
  sibling private overlay when present.
- Running from `private-config` wrappers loads both when the public repo is
  present.
- The private overlay path can be supplied by `PRIVATE_REPO_DIR` or
  `--private-repo`.

Example:

```toml
[[entries]]
owner = "public"
path = ".zshrc"
mode = "link"

[[entries]]
owner = "public"
path = ".codex/config.toml"
mode = "merge"
strategy = "codex-top-level-keys"

[[entries]]
owner = "private"
path = ".zshenv"
mode = "link"

[[entries]]
owner = "private"
path = ".claude/skills"
mode = "link"
```

Special cases should be manifest-declared and implemented by typed Go
strategies. The manifest must not become a scripting language.

Initial entry modes:

```text
link
merge
warn
```

### Workspace Manifest

External workspace links should be generic and manifest-driven:

```toml
[[workspaces]]
name = "oss"
local = "/Users/xj/github/oss"
external = "/Volumes/xj-daily/dev/oss"
required = false
```

`workspace status` should warn when optional external paths are unavailable.
`workspace verify` should fail only for invariants selected by the command or
profile.

## Domains

### home

`home` owns repo-to-`$HOME` topology:

- install planning
- symlink or copy apply
- backup creation
- live-path resolution
- owner verification
- public-only bootstrap behavior
- legacy Mackup drift checks when relevant

Current shell install behavior to preserve:

- symlink mode default
- copy mode supported but secondary
- dry-run planning
- target backup before replacement
- public install can call private overlay when available
- private overlay can be skipped
- Codex config uses a controlled merge strategy
- tmux legacy state can produce warnings

### app

`app` contains only app-specific deterministic workflows. It is not an app
inventory.

Initial app workflow:

```text
app typewhisper validate
app typewhisper status
app typewhisper import
app typewhisper export
```

Selective validators may follow:

```text
app terminal verify
app nvim verify
app lazygit verify
app karabiner verify
```

`app terminal verify` can own cross-app invariants for Ghostty, tmux, and
Karabiner terminal key behavior.

### app typewhisper

TypeWhisper is the first real vertical slice.

Requirements:

- Parse and validate repo-owned `lexicon.json`.
- Count live dictionary terms, corrections, and snippets.
- Export live stores to JSON.
- Import by upsert only.
- Create timestamped backups before writes.
- Refuse to write while `TypeWhisper.app` is running by default.
- Allow `--allow-running` as an explicit unsafe override.
- Allow dry-run while the app is running.

Default import remains upsert-only. Reconcile and prune are future commands and
require a separate ownership marker strategy before deletion exists.

### agent

`agent` owns Claude/Codex runtime topology:

- policy link status and verification
- skill discovery link status and verification
- skill sync
- Codex auth snapshot switching

`tools/skillsctl` remains separate during the first milestone. Later,
`configctl agent skills` can reuse or replace that logic.

Codex auth constraints:

- never print token contents
- report mode and snapshot presence only
- validate JSON before save/use
- always back up current `auth.json` before switching
- no automatic login flow
- no remote provider decisions

### package

`package` is ledger/audit focused in v1.

It should inspect:

- private `Brewfile`
- public `Brewfile`
- private `npm-globals.txt`
- public `npm-globals.txt`
- installed Homebrew formulae/casks
- installed global npm packages

It should report:

- tracked but missing packages
- installed but untracked packages
- packages tracked in both repos
- app config present without package ledger support

It should not install or remove packages in v1.

### workspace

`workspace` owns symlink-only external workspace mounts such as:

```text
oss: /Users/xj/github/oss -> /Volumes/xj-daily/dev/oss
```

Commands should be generic and manifest-driven:

```text
workspace status
workspace verify [name]
workspace link <name> [--dry-run]
```

`link` must refuse to overwrite real directories. It can replace missing paths
or symlinks only.

### storage

`storage` stays in the north-star design but is not part of the first
implementation milestone.

When added:

- `storage audit` measures only
- `storage plan` suggests cleanup actions
- no deletion in v1
- no network dependency by default
- slow checks must not be in default `verify`

## Git State

`configctl` may inspect git state but must not mutate it.

`status` may report:

- repo branch
- dirty count
- staged count
- untracked count
- whether managed files overlap dirty paths

The only Git-mutating surface is `release capture`, which stages declared
paths and commits only when `--apply` is passed. No commands should exist for
amend, reset, rebase, checkout, or force-push.

## Taskfile Migration

Root Taskfiles should become compatibility aliases and composition only.

Target examples:

```yaml
tasks:
  install:
    cmds:
      - tools/configctl/bin/configctl home apply {{.CLI_ARGS}}

  install:dry-run:
    cmds:
      - tools/configctl/bin/configctl home plan {{.CLI_ARGS}}

  doctor:
    cmds:
      - tools/configctl/bin/configctl verify

  verify:ownership:
    cmds:
      - tools/configctl/bin/configctl home verify
```

During migration, Taskfiles may still call existing scripts for commands not yet
ported. The end state is no business logic in Taskfile shell blocks.

## Compatibility

Keep exact-path wrappers only when an external caller still needs them. New
documentation should use the `configctl` command directly.

## Roadmap

### Milestone 0: Design

- Add this design document.
- Record accepted command tree, safety model, manifests, output envelope, and
  roadmap.

### Milestone 1: TypeWhisper Vertical Slice

- Scaffold `tools/configctl`.
- Implement Kong command tree foundation.
- Implement common result envelope and diagnostics.
- Implement `app typewhisper validate/status/import/export`.
- Port TypeWhisper schema and SQLite logic to Go.
- Add tests for schema validation and import planning.
- Prefer `configctl app typewhisper` directly; keep no generic TypeWhisper
  wrapper unless an external caller needs an exact path.
- Update TypeWhisper README.

### Milestone 2: Home Topology

- Add split `configctl/home.toml` manifests.
- Implement `home status/resolve/plan/apply/verify`.
- Preserve symlink and copy modes.
- Implement backups and controlled merge strategies.
- Move install and representative ownership checks behind `configctl`.
- Update Taskfile install and ownership wrappers.

### Milestone 3: Agent Topology

- Implement `agent status/verify`.
- Implement `agent policy status/verify`.
- Implement `agent skills list/verify/sync`.
- Implement `agent codex-auth status/save/use`.
- Decide whether `skillsctl` remains standalone or becomes shared logic.

### Milestone 4: Package and Workspace Audits

- Implement package ledger status/audit/verify.
- Add workspace manifest.
- Implement workspace status/verify/link.
- Update `doctor` compatibility alias to use structured checks.

### Milestone 5: App Validators and Storage

- Move terminal, nvim, lazygit, and karabiner validators under `app`.
- Add storage audit/plan as read-only measurement commands.
- Keep slow or environment-dependent checks out of default `verify`.

## Work Tracking

`W-0004` is the umbrella work item for the full `configctl` program. Later
implementation milestones may get narrower work items, but they should link
back to `W-0004` in their work-space notes.
