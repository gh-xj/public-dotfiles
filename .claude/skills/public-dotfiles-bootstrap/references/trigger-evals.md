# Trigger Evals

Use these lightweight cases when editing the skill description or routing
boundaries.

## Should Trigger

| Prompt | Expected Reason |
| --- | --- |
| `mbook trackpad still does not tap-to-click after bootstrap` | target Mac discrepancy after bootstrap |
| `bootstrap a clean Mac from public-dotfiles` | new-machine bootstrap workflow |
| `Raycast settings did not converge on the target Mac` | app preference drift in public baseline |
| `source Mac and target Mac differ in Dock/display/input behavior` | source-vs-target convergence audit |
| `which macOS settings should become repo-owned harness?` | public/private and layer ownership decision |

## Should Not Trigger

| Prompt | Better Owner |
| --- | --- |
| `remove an unused npm package from my config` | `config-manager`, unless part of bootstrap drift |
| `edit my Neovim keymap` | `config-manager` |
| `clean private-config secrets` | private repo workflow / security-specific guidance |
| `write a generic Nix module` | ordinary Nix/code workflow |
| `design a new Claude/Codex skill` | `skill-builder` |
