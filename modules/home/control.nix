{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
in {
  config = lib.mkIf cfg.enable {
    xdg.configFile."public-dotfiles/generation.json".text = builtins.toJSON {
      schema = 1;
      source_revision = cfg.sourceRevision;
      source_fingerprint = builtins.hashString "sha256" (toString ../..);
    };
    # Detach while the old managed links still exist, before cleanOldGen can
    # remove them. This preserves account/private hook bytes during migration.
    home.activation.detachMutableAgentConfigs = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      agent_config_mode=--apply
      if [ -n "''${DRY_RUN:-}" ]; then agent_config_mode=--dry-run; fi
      ${pkgs.python3}/bin/python3 ${../../scripts/public-control.py} \
        --repo ${lib.escapeShellArg cfg.repoRoot} \
        --home ${lib.escapeShellArg config.home.homeDirectory} \
        detach-agent-configs "$agent_config_mode"
    '';
    assertions = map (name: {
      assertion = !(builtins.any (entry: entry.enable && entry.target == name) (builtins.attrValues config.home.file));
      message = "Mutable agent settings must use seeds, not home.file links: ${name}. Preserve private additions in the live file.";
    }) [ ".claude/settings.json" ".codex/config.toml" ".codex/hooks.json" ];
  };
}
