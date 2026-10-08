# Migrate an existing work Mac off nix-darwin

This is the canonical cutover for a work Mac that keeps only the public
baseline, or composes it with a public-safe work overlay. It preserves
Determinate Nix and replaces nix-darwin with standalone Home Manager. For a
fresh public-only Mac, use [bootstrap.md](bootstrap.md).

Run ordinary commands as the logged-in user. Commands marked **human only**
may prompt or use sudo; an agent may prepare and verify, but must not run them.

## Migration checklist

- [ ] Confirm prerequisites and choose public-only or overlay ownership
- [ ] Convert and build the standalone Home Manager profile
- [ ] Pin the current nix-darwin system as a rollback anchor
- [ ] Tear down nix-darwin with the human present
- [ ] Apply Home Manager from the owning repository
- [ ] Open a clean shell, then install apps and runtimes
- [ ] Reapply any overlay-owned root policy after mosh exists
- [ ] Check, run doctor, and complete interactive setup
- [ ] Keep, test, then retire the rollback anchor

## 1. Confirm prerequisites and owner — human or agent

The Mac must already use Determinate Nix, Homebrew, and nix-darwin:

```bash
test -f /etc/nix/nix.conf
test -f /Library/LaunchDaemons/systems.determinate.nix-daemon.plist
test -x /run/current-system/activate
command -v brew
```

Expected: no `test` output and a Homebrew executable path. Stop if Determinate
Nix is absent: teardown must not remove the machine's only Nix daemon.

Clone or update the public checkout, then choose one owner for activation:

```bash
if [[ -d ~/public-dotfiles/.git ]]; then
  git -C ~/public-dotfiles pull --ff-only
else
  git clone https://github.com/gh-xj/public-dotfiles.git ~/public-dotfiles
fi
git -C ~/public-dotfiles status --short --branch
```

Expected: a clean branch. Public-only uses `~/public-dotfiles`. An overlay uses
its own repository for Home Manager activation and imports the public module as
shown next; it must not patch the public checkout.

## 2. Prepare the standalone profile — human or agent

### Public-only

No host file is needed. Build and check with the temporary tools that remain
available even if nix-darwin currently owns `task`:

```bash
cd ~/public-dotfiles
nix shell nixpkgs#go-task nixpkgs#gitleaks -c task check
nix shell nixpkgs#go-task nixpkgs#gitleaks -c task plan
```

Expected: `public dotfiles check passed` and a plan for a `/nix/store/...`
activation generation.

### Work overlay

Remove the overlay's `nix-darwin` input, its `nixpkgs` follow, every
`darwinConfigurations` output, and all `system.*`, `users.users`, `homebrew.*`,
`services.*`, and `xj.publicDotfiles.darwin` options. Its flake must retain this
shape (replace the profile and system with the local values):

```nix
homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
  pkgs = import nixpkgs { system = "aarch64-darwin"; };
  modules = [ public.homeModules.default ./host.nix ];
};
```

The host module declares `home.username`, `home.homeDirectory`,
`home.stateVersion`, `programs.home-manager.enable = true`, and:

```nix
xj.publicDotfiles = {
  enable = true;
  repoRoot = "${config.home.homeDirectory}/public-dotfiles";
  tmuxRecovery.enable = true; # optional; off by default
};
```

The complete public-safe fixture is in `examples/downstream/`. Pin the public
input in the overlay lock and make its `check`, `plan`, `apply`, and `doctor`
commands target the named `homeConfigurations` entry; its doctor calls the
public one with `EXTRA_BREWFILE` and `OVERLAY_DIR`. Verify from the overlay:

```bash
task check
task plan
```

Expected: both the overlay and imported public checks pass, and the plan names
the intended standalone Home Manager profile. Do not continue on a build or
identity mismatch.

## 3. Pin the nix-darwin rollback anchor — human or agent

Do this immediately before teardown:

```bash
current_system="$(readlink -f /run/current-system)"
test -x "$current_system/activate"
mkdir -p ~/.local/state/darwin-rollback
nix-store --realise "$current_system" \
  --add-root ~/.local/state/darwin-rollback/system --indirect
readlink ~/.local/state/darwin-rollback/system
```

Expected: both `nix-store` and `readlink` print the same
`/nix/store/...-darwin-system-...` target. This indirect GC root is the system
rollback point; do not garbage-collect or delete it during the cutover.

## 4. Tear down nix-darwin — human only

If the work overlay owns a reviewed `scripts/root.sh` with the documented
interface below, preview and use its narrow teardown:

```bash
scripts/root.sh --dry-run teardown-darwin
sudo scripts/root.sh teardown-darwin
```

Expected: the preview says nothing changed; the real run ends with
`nix-darwin removed; Determinate Nix preserved.` The helper removes
`/etc/pam.d/sudo_local`, so the **next** sudo asks for the login password rather
than Touch ID.

For a public-only checkout, no public root helper is declared. Use
nix-darwin's own pinned uninstaller instead:

```bash
sudo ~/.local/state/darwin-rollback/system/sw/bin/darwin-uninstaller
```

Expected: its plan is printed, the human confirms it, and it ends with `Done!`.
It intentionally leaves old `/nix/var/nix/profiles/system*` links; keep them
until final verification, then remove them only under the machine owner's
normal cleanup policy.

For either route, verify:

```bash
test ! -e /run/current-system
test ! -e /etc/pam.d/sudo_local
launchctl print system/systems.determinate.nix-daemon >/dev/null
```

Expected: no output and exit status zero. If teardown fails, stop and use the
system rollback below before making further changes.

## 5. Apply standalone Home Manager — human only

From the selected owner repository:

```bash
task apply
readlink ~/.local/state/nix/profiles/home-manager
```

Expected: activation completes and the link names a `home-manager-*-link`.
Do not use sudo or `darwin-rebuild` for this step.

Already-open shells and agents retain stale `PATH` and possibly
`NIX_SSL_CERT_FILE`. Open a new shell. Agents must verify through a clean one:

```bash
env -i HOME="$HOME" USER="$USER" /bin/zsh -lc \
  'command -v task; print -r -- ${NIX_SSL_CERT_FILE-unset}'
```

Expected: `task` comes from the standalone Home Manager profile and the second
line is `unset`.

## 6. Install apps and locked runtimes — human only

Always run the canonical public app task. An overlay that keeps its own work
apps in a Brewfile passes it; public-only omits `EXTRA_BREWFILE`:

```bash
task --dir ~/public-dotfiles apps EXTRA_BREWFILE="$PWD/Brewfile"
brew bundle check --file ~/public-dotfiles/Brewfile --no-upgrade
mise ls --current
```

Expected: Brew reports the bundle satisfied and mise lists locked versions.
Apps that only came from the old, larger public Brewfile stay installed; move
the ones this Mac needs into the overlay Brewfile and uninstall the rest by
hand. If a cask links a Homebrew Python (for example `gcloud-cli`), `brew
unlink` that dependency so Python resolves through mise. If mise prompts despite the checked-in
trust setting and `.zshenv`, inspect the path, then trust only the canonical
file:

```bash
mise trust ~/.config/mise/config.toml
mise trust --show ~/.config/mise/config.toml
```

Expected: mise reports that file as trusted. Never use `brew bundle cleanup`.

## 7. Reapply overlay root policy — human only

Skip this step for public-only. If the work overlay owns the `scripts/root.sh`
`apply` operation, run it only now, after the overlay Brewfile's `mosh` is installed. First
verify the helper and its interface:

```bash
test -x scripts/root.sh
scripts/root.sh --help 2>&1 | rg 'teardown-darwin|apply'
test -x /opt/homebrew/bin/mosh-server
scripts/root.sh --dry-run apply
sudo scripts/root.sh apply
```

Expected: the executable test passes, dry-run has no missing-mosh warning, and
the real run reports completion. Running root apply before apps is wrong: the
reference helper exits with `Install the declared Homebrew mosh formula before
root.sh apply.`

## 8. Verify the cutover — human or agent

From the selected owner repository, using a clean shell:

```bash
env -i HOME="$HOME" USER="$USER" /bin/zsh -lc '
  task check && task doctor
  command -v docker
  command -v python3
'
```

Expected: checks pass, provenance reports `0 issue(s)`, Docker resolves below
`~/.orbstack/bin`, and Python below mise.

If doctor reports duplicate or shadowed owners, inspect all providers and
hard-coded Homebrew paths before uninstalling anything:

```bash
type -a gh node npm go cargo bun python3
git -C ~/public-dotfiles grep -n '/opt/homebrew/bin/' -- . || true
```

Remove the extra Homebrew formula, `npm -g` package, `~/go/bin`,
`~/.cargo/bin`, `~/.bun/bin`, or old npm-global prefix; use `brew unlink
<formula>` when it is only a dependency. If startup still mentions a removed
binary, run `rm -f ~/.cache/*-init.zsh(N)` and open another clean shell.
Git-ignored runtime trees under live-linked config, such as a legacy
`~/.config/nvim/plugged/`, are not config and `task check` skips them. Cleanup
is optional; Neovim loads plugins from `~/.local/share/nvim/lazy`, so moving
the tree to the Trash is safe while sessions stay open.

Generic improvements found on this Mac go upstream as proposals, not overlay
forks: see [upstream proposals](downstream-composition.md#upstream-proposals).
Complete TCC grants, work account sign-ins, Raycast Cloud Sync, and app
first-run dialogs manually. Hand-edited config now uses live repo links;
agent settings stay writable and re-merge declared keys on apply. Config-only edits need no apply. Reload
tmux with `tmux source-file ~/.tmux.conf` and use Ghostty's Reload
Configuration action. Package/module changes still require `task apply`.

## 9. Roll back or retire the anchor — human only

To restore nix-darwin while the anchor exists:

```bash
sudo ~/.local/state/darwin-rollback/system/activate
readlink /run/current-system
```

Expected: activation completes and `readlink` prints the anchored
`/nix/store/...-darwin-system-...` target. Reopen shells afterward.

Keep the anchor until standalone shell startup, SSH if overlay-owned, mosh,
tmux, editor, agents, and a reboot have all passed. Then delete only this link:

```bash
rm ~/.local/state/darwin-rollback/system
test ! -e ~/.local/state/darwin-rollback/system
```

Expected: no output. The store closure becomes eligible for later garbage
collection; the command does not delete it immediately.
