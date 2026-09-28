# Agent Config Baseline

`public-dotfiles` owns the reusable, publishable agent baseline for Claude and
Codex.

## Codex ownership

Keep each Codex layer single-owned:

| Layer | Owner |
| --- | --- |
| CLI executable | Official standalone installer; `~/.local/bin/codex` points into `~/.codex/packages/standalone` |
| Desktop app | Homebrew cask `codex-app`; its bundled executable is app-internal, not the shell CLI |
| Public policy/defaults | This repo: `.claude/CLAUDE.md`, `.codex/rules`, `config/codex/config.toml`, and `config/codex/hooks.json` |
| Private skills and account-specific declarations | `private-config` |
| Auth, sessions, trust, plugin registries, caches, and mutable config | Live real directory `~/.codex`; never a repo parent symlink |

Install or update the shell CLI with the official standalone installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Do not add `pkgs.codex`, `@openai/codex`, or another Homebrew CLI package. The
desktop cask and standalone CLI are separate surfaces.

## Public paths

Live paths owned by Home Manager:

- `~/AGENTS.md`
- `~/.claude/CLAUDE.md`
- `~/.claude/statusline-command.sh`
- `~/.codex/AGENTS.md`
- `~/.codex/rules/default.rules`

`~/AGENTS.md`, `~/.claude/CLAUDE.md`, and `~/.codex/AGENTS.md` are all
generated from the same public policy source, `.claude/CLAUDE.md`. The home
root file exists so Codex sees the same baseline when it walks ancestor
directories outside a repo.

Template path owned by the public repo:

- `config/codex/config.toml`
- `config/claude/settings.json`

Claude settings use the same mutable-seed contract: first activation creates a
writable file and migrates old managed links; later activations preserve live
edits. Hooks call installed `agent-session` and `agent-pane-title` helpers.
The statusline synchronizes documented Claude names into pane labels; see
`docs/ghostty-tmux.md`. Existing regular settings files are deliberately not
merged: review the seed diff and opt into desired hooks/preferences manually.
Global shell guards and formatters are no longer installed.

The public Codex template stores reusable baseline settings such as model,
theme, and feature defaults. Bootstrap copies it to `~/.codex/config.toml` only
when that live file is missing or still points at an old read-only public Home
Manager generation. Home Manager must not own the live Codex config because
Codex writes project trust and other runtime state there.
Keep the project-local reserved `.codex/config.toml` path empty so Codex does
not parse the seed template as repo config.

For the general public config ownership and delivery classes used across Home
Manager modules, see `docs/config-delivery-model.md`.

Project-local public skills may live in this repo when they operate this repo
itself. The canonical source for those skills is `.claude/skills/`, with
`.agents/skills/` reserved for Codex discovery adapters when needed. These are
not global home skill trees and are not linked into `~/.claude/skills` or
`~/.codex/skills` by the public Home Manager module.

## What stays private

Keep these in `private-config` or as live runtime state:

- `~/.claude/settings.local.json`
- `~/.claude/plugins/`
- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.codex/superpowers/`
- `~/.codex/auth.json`
- mutable `~/.codex/config.toml` runtime sections
- per-project trust lists
- custom provider endpoints
- sessions, history, caches, logs, and telemetry

## Intent

The public repo should expose stable behavior and baseline ergonomics, not
account-specific state. If a setting names a private endpoint, hard-codes a
personal workspace list, or depends on local auth material, it does not belong
here.

## Bootstrap Sequence

Build the public Home Manager example without applying it:

```bash
nix build .#
```

To apply the public baseline directly on a standalone machine, clone the repo
and run:

```bash
task apply
```

For private machines, `private-config` imports this public baseline and adds
only private overlay state:

- `~/.claude/settings.local.json`
- plugins, skills, auth, trust lists, mutable Codex config sections, and
  provider overrides

## Verification

Run this gate after changing Codex config policy:

```bash
task check
```
