# Downstream data, public implementation

A separate flake imports `public.homeModules.default` and supplies local data.
Start from `examples/downstream/flake.nix` and `host.nix` in your private owner.
Existing nix-darwin consumers should follow
[the standalone migration](migrate-work-mac.md).
The fixture deliberately uses only synthetic identities; do not put a real
host or provider command back into this repo.
Pin public in the downstream lock, then update that pin explicitly after rebase.
Build with `nix build .#homeConfigurations.<profile>.activationPackage`; activate
through the downstream's normal switch.

| Input under `xj.publicDotfiles` | Ownership / behavior |
| --- | --- |
| `repoRoot` | Local checkout path; username/home remain normal Home Manager fields |
| `agents.policy.extraText` | Private policy appended to the one shared Claude/Codex policy artifact |
| `agents.codexHooks.seed.enable = false` | Public does not install, seed, detach, assert ownership of or otherwise claim Codex hooks |
| `agents.claudeSettings.seed.enable = false` | Public does not seed, migrate, detach or claim mutable Claude settings; public statusline and helper delivery remains enabled |
| `agents.codexRules.extraText` | Genuinely downstream-only rules; generic proven rules belong in main |
| `workmux.agent`, `workmux.extraAgents.<name>.argv`, `.type` | Provider selection and trusted argv; no source-file patch required |
| `workmux.extraConfig` | Additional YAML-compatible configuration; `status_format` remains false |
| `tmuxRecovery.*` | Opt-in public engine, retention and optional schedule; trusted adapter file remains downstream |
| `scratchGc.enable = false` | Public creates no scratch package/home target; private owner may claim it directly |
| `scratchGc.package` with `.enable = true` | Optional delivery of a complete downstream package, not a public scratch implementation |

The public Workmux base remains `.config/workmux/config.yaml`, expressed as JSON
(valid YAML) so Nix can read it without an extra parser or duplicated defaults.
Home Manager renders that base plus typed overrides to a store-backed config.
Provider argv is shell-quoted by the public module. Keep credentials out of argv
and settings literals; a private provider adapter should obtain them at runtime.

The downstream fixture claims its own hooks and scratch target to prove that
neither needs `home.file.<path>.enable = lib.mkForce false`. Real hook ownership
must retain mutable account/plugin edits. Disabling the public hook seed means
the private owner also owns merging the required public integration hooks; the
doctor continues to offer its sanitized merge plan without applying it.

When a private owner retains Claude settings and reporter/account hooks (including
a `.claude` parent symlink into its repository), set
`xj.publicDotfiles.agents.claudeSettings.seed.enable = false;` while keeping
`agents.hooks.enable = true;`. This excludes `.claude/settings.json` from generation
`mutable_targets` and pre-link detachment, without disabling
`.claude/statusline-command.sh`, `agent-pane-title`, `agent-session`, or
`agent-workmux-status`. The default is true for standalone installs. The private
owner preserves the live settings and merges required public integration itself.
The read-only doctor reports missing integration; do not disable all helper delivery.

## Migration checklist

1. Move the local host into the private flake; import the public module rather
   than adding a home configuration to the public flake. Keep local install/check
   wrappers in that owner, not as public Taskfile patches.
2. Move provider commands into Workmux data, policy into `extraText`, and provider
   resume commands into the JSON/TOML recovery adapter file. Built-in overrides
   and extra provider names are supported without editing the recovery engine.
3. Disable public Codex-hook seeding if a private owner manages it. Remove the
   old `home.file` disabling override. Keep required identity/status hooks when
   merging private hooks; retain app hook trust review.
4. Keep scratch ownership disabled unless deliberately supplying a full private
   package. No public scratch policy requires a machine-specific CLI.
5. Set `tmuxRecovery.enable = true`, enable its schedule and interval 300 only when ready
   to replace the old scheduler. Disable the old private job explicitly in its
   owner to avoid duplicate scheduling. Keep the legacy checkpoint archive:
   new retention never claims it, and old formats need explicit migration.
6. Drop downstream patches to `.claude/CLAUDE.md`, `.codex/rules/default.rules`,
   `.config/workmux/config.yaml`, `global/Taskfile.yml`, the public `Taskfile.yml`,
   `flake.nix`, `scripts/tmux-recovery.py`,
   `modules/home/recovery.nix`, `modules/home/composition.nix`, the agent modules,
   `modules/home/control.nix`, `modules/home/config-files.nix`, and recovery docs.
   These files remain in main; remove the overlay patches, not the upstream files.

The public check builds the standalone example without activation. A downstream
owner verifies its composed profile through its own canonical check.
