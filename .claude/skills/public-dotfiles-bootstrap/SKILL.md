---
name: public-dotfiles-bootstrap
description: Use when bootstrapping or auditing public-dotfiles on a new Mac, comparing source and target Mac discrepancies, handling public/private boundaries, or deciding whether macOS, Raycast, display, trackpad, package, or app drift belongs in the repo.
---

# Public Dotfiles Bootstrap

Router for restoring and auditing the public, standalone Mac baseline.

## Route Elsewhere

- General app cleanup: `config-manager`.
- Cross-surface persistence: `harness-router`.
- Generic skill design: `skill-builder`.
- Sensitive, account-bound, company/private, secret-adjacent, session, cache,
  credential, or machine-local state: the private owner.

## Workflow

1. Run `git status --short --branch`; read `AGENTS.md`, `README.md`, and the
   relevant `docs/bootstrap.md` or `docs/macos-convergence-model.md` section.
2. Identify source/target Macs and inspect the controlling layer. `defaults`
   alone is insufficient for ByHost, GUI cache, TCC, display, or IOKit state.
3. Classify ownership, then encode public-safe desired state in repo source.
4. Add a verifier only when declaration/build cannot prove observable behavior.
5. Run the narrow non-mutating gate, then `task check`.
6. Apply only when explicitly requested, following `docs/bootstrap.md`; commit
   according to `AGENTS.md` and run `task check` (it scans staged changes for secrets).

Known gaps: source/target comparison is manual; Raycast registration remains
interactive; trackpad behavior may require a GUI-session reload after apply.
