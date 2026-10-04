{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
  mutableTargets = lib.optionals cfg.agents.policy.enable [ ".codex/config.toml" ]
    ++ lib.optionals (cfg.agents.hooks.enable && cfg.agents.claudeSettings.seed.enable) [ ".claude/settings.json" ]
    ++ lib.optionals (cfg.agents.hooks.enable && cfg.agents.codexHooks.seed.enable) [ ".codex/hooks.json" ];
  yaziPackage = lib.findFirst (package: lib.getName package == "yazi") null config.home.packages;
  ownedPrograms = lib.optionalAttrs (yaziPackage != null) {
    yazi = { owner = "nix"; version = yaziPackage.version; };
    ya = { owner = "nix"; version = yaziPackage.version; };
  };
  allMutableTargets = [ ".claude/settings.json" ".codex/config.toml" ".codex/hooks.json" ];
  downstreamTargets = builtins.filter (name:
    builtins.any (entry: entry.enable && entry.target == name) (builtins.attrValues config.home.file)
  ) allMutableTargets;
  legacyOnlyTargets = builtins.filter (name: !(builtins.elem name mutableTargets)) allMutableTargets;
in {
  config = lib.mkIf cfg.enable {
    xdg.configFile."public-dotfiles/generation.json".text = builtins.toJSON {
      schema = 1;
      mutable_targets = mutableTargets;
      owned_programs = ownedPrograms;
    };
    # Validate before the write boundary: HM otherwise follows parent symlinks
    # and may write through an unknown Ghostty directory owner.
    home.activation.checkGhosttyParent = lib.mkIf config.programs.ghostty.enable (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [ -L ${lib.escapeShellArg "${config.xdg.configHome}/ghostty"} ]; then
          echo "Ghostty parent is a symlink; resolve its ownership before activation" >&2
          exit 1
        fi
      ''
    );
    # cleanOldGen lives inside linkGeneration in the pinned Home Manager.
    # Preserve bytes after all read-only checks, but before old links disappear.
    home.activation.detachMutableAgentConfigs = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
      agent_config_mode=--apply
      if [[ -v DRY_RUN ]]; then agent_config_mode=--dry-run; fi
      ${pkgs.python3}/bin/python3 ${../../scripts/public-control.py} \
        --repo ${lib.escapeShellArg cfg.repoRoot} \
        --home ${lib.escapeShellArg config.home.homeDirectory} \
        detach-agent-configs --old-generation "''${oldGenPath:-}" \
        ${lib.concatMapStringsSep " " (name: "--skip ${lib.escapeShellArg name}") downstreamTargets} \
        ${lib.concatMapStringsSep " " (name: "--legacy-only ${lib.escapeShellArg name}") legacyOnlyTargets} "$agent_config_mode"
    '';
    assertions = map (name: {
      assertion = !(builtins.any (entry: entry.enable && entry.target == name) (builtins.attrValues config.home.file));
      message = "Mutable agent settings must use seeds, not home.file links: ${name}. Preserve private additions in the live file.";
    }) mutableTargets;
  };
}
