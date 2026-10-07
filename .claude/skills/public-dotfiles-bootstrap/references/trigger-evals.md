# Trigger Evals

Use these cases when editing the skill description or routing boundary.

## Should Trigger

| Prompt | Expected Reason |
| --- | --- |
| `trackpad still does not tap-to-click after bootstrap` | target-Mac discrepancy after bootstrap |
| `bootstrap a clean Mac from public-dotfiles` | new-machine bootstrap workflow |
| `Raycast settings did not converge on the target Mac` | app preference drift in the public baseline |
| `source and target Macs differ in Dock, display, or input behavior` | convergence audit |
| `which macOS settings should become repo-owned?` | ownership and layer decision |

## Should Not Trigger

| Prompt | Better Owner |
| --- | --- |
| `remove an unused npm package from my config` | `config-manager` |
| `edit my Neovim keymap` | `config-manager` |
| `clean private secrets` | private repo workflow |
| `write a generic Nix module` | ordinary Nix/code workflow |
| `design a new Claude/Codex skill` | `skill-builder` |

## Output Invariants

- Inspect the owning Nix module, ledger, and live layer before proposing a fix.
- Do not treat a matching `defaults read` value as proof of matching behavior.
- Keep selected input source, TCC grants, sessions, caches, and app-owned
  registration out of public desired state.
- Use only tasks listed by `task --list-all`; finish with `task check`.
