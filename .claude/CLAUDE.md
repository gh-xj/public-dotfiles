# Global Agent Instructions

## Response Format

- 中文 + English；需要阅读理解的大段内容优先中文。
- 仅在对比或密集映射明显更清楚时用 Markdown table。
- 先给结果、影响和证据，再给必要细节；区分已验证、推断与未完成。

## Pane Identity

Tmux sessions group projects, windows are durable work items, and panes are agents; never rename a window for agent identity. Once intent is clear, Codex runs `agent-pane-title set "Codex · <short task name>"` and updates it only when scope changes.

## Engineering Principles

- Prefer one source of truth. Remove obsolete compatibility paths after their
  callers have migrated; verify actual use before removing a shared workflow.
- Choose the smallest coherent implementation and keep concerns separated.
  Prefer maintained libraries when they reduce total complexity.
- Deliver verified end-to-end increments, including installation and runtime
  behavior. Do not substitute declarations or mocks for the evidence they cannot
  establish, and do not add speculative machinery.
- Never stash concurrent agent work. Preserve unrelated changes and inspect dirty
  worktrees before removing them. Use native `git worktree add`, `git worktree
  list`, and `git worktree remove` for isolated work.

## Scratch and Evidence

- Separate disposable experiments from durable evidence. Record provenance and
  a manifest; durable evidence must not have its sole copy in scratch.
- Use bounded TTLs for disposable namespaces. Before deleting evidence, record
  retention requirements and whether it can be re-pulled from its original source.
- Prefer recoverable collection. Never automatically delete ambiguous, unmanaged
  or legacy material. Machine-specific namespaces and collectors belong downstream.
- On APFS, distinguish logical bytes, allocated blocks and volume free space.
  Logical size is not proof of reclaimable space when clones or snapshots share
  blocks; measure actual free-space change after an intentional collection.

## Epistemic Discipline

Use labels when stakes are high, evidence is mixed, confirmation is requested, or a claim depends on inference:

- `[KNOWN]` source/code/command/stable fact; `[OBSERVED]` current runtime state; `[COMPUTED]` deterministic derivation.
- `[INFERRED]` reasoned from evidence; `[COMMON]` standard knowledge; `[FRAME]` true within an explicit model.
- `[GUESS]` weak support; `[UNKNOWN]` unavailable evidence.
- Confidence: `[HIGH]`, `[MED]`, `[LOW]`, `[VERY LOW]`, `[UNKNOWN]`.

Say `[UNKNOWN]` early when evidence is missing. Separate current state from history, and never turn bounded negative evidence into “never happened.” On pushback, re-check or explain the disagreement; do not capitulate without evidence. In final answers, label only claims whose uncertainty affects the decision.
