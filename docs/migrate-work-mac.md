# Migrate a downstream Mac to standalone Home Manager

1. Rebase the downstream branch onto the public commit that removes
   `darwinModules`.
2. Remove the `nix-darwin` input, its `nixpkgs` follow, and every
   `darwinConfigurations` output from the downstream flake.
3. Keep importing `public.homeModules.default`; replace the host output with:

```nix
homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
  pkgs = import nixpkgs { system = "aarch64-darwin"; };
  modules = [ public.homeModules.default ./host.nix ];
};
```

4. In `host.nix`, delete `xj.publicDotfiles.darwin`, `system.*`, `users.users`,
   `homebrew.*`, `services.*` and other nix-darwin options. Declare
   `home.username`, `home.homeDirectory`, `home.stateVersion`, and
   `programs.home-manager.enable` instead.
5. Point downstream `plan`/`apply` at
   `homeConfigurations."user@host".activationPackage` and `home-manager switch
   --flake .#user@host`; no sudo or `darwin-rebuild` remains.
6. Before cutover, build the activation package with `nix build --no-link` and
   run both downstream and public `task check`.
7. With the machine owner present, run the separately owned one-time root
   teardown, then downstream `task apply` and `task apps`.
8. Start a fresh login and non-login zsh and verify they resolve the same PATH,
   Home Manager profile, mise shims, Homebrew and Nix commands.
