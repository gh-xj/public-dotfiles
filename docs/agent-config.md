# Agent Config Baseline

`public-dotfiles` owns the reusable, publishable agent baseline for Claude and
Codex.

## Public paths

- `~/.claude/CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/`
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/config.toml`
- `~/.codex/rules/default.rules`

## What stays private

Keep these in `private-config` or as live runtime state:

- `~/.claude/settings.local.json`
- `~/.claude/plugins/`
- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.codex/superpowers/`
- `~/.codex/auth.json`
- per-project trust lists
- custom provider endpoints
- sessions, history, caches, logs, and telemetry

## Intent

The public repo should expose stable behavior and baseline ergonomics, not
account-specific state. If a setting names a private endpoint, hard-codes a
personal workspace list, or depends on local auth material, it does not belong
here.

## Bootstrap Sequence

Use the same command in both states:

```bash
task install
```

If the machine only has `public-dotfiles`, that installs the public agent
baseline and skips the private layer. If `private-config` is added later beside
this repo, rerun the same command and it will layer in:

- `~/.claude/settings.local.json`
- plugins, skills, auth, trust lists, and provider overrides

If the machine should keep a private overlay but cannot access the real private
repo, run:

```bash
task private:init
```

That scaffolds a sibling `../private-config` as a local-only git repo. The
scaffolded repo owns only the paths listed in `private-paths.txt`, and its
installer skips entries whose source files do not exist yet.

Use flags only when needed:

```bash
task install -- --public-only
task install -- --dry-run
```

If `PRIVATE_REPO_DIR` is explicitly set, a missing path is an error. If the
default sibling `../private-config` is absent, install continues without the
private overlay.
