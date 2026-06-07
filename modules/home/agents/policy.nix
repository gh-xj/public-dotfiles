{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.agents.policy;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      ".claude/CLAUDE.md".source = ../../../.claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ../../../.claude/CLAUDE.md;
      ".codex/rules" = {
        source = ../../../.codex/rules;
        force = true;
      };
    };

    home.activation.seedCodexConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      target="${config.home.homeDirectory}/.codex/config.toml"
      seed=0

      if [ -L "$target" ]; then
        link_target="$(readlink "$target" 2>/dev/null || true)"
        case "$link_target" in
          /nix/store/*/.codex/config.toml|/nix/store/*/config/codex/config.toml)
            seed=1
            ;;
        esac
      elif [ ! -e "$target" ]; then
        seed=1
      fi

      if [ "$seed" -eq 1 ]; then
        $DRY_RUN_CMD rm -f "$target"
        $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/.codex"
        $DRY_RUN_CMD install -m 600 ${../../../config/codex/config.toml} "$target"
      elif [ ! -w "$target" ]; then
        echo "warning: $target is not writable; Codex project trust prompts may fail" >&2
      fi
    '';
  };
}
