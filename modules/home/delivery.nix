{ config, lib, pkgs, ... }:

let
  cfg = config.xj.publicDotfiles;
  repoRootPath = ../..;
  mkStorePath = rel: repoRootPath + "/${rel}";
  mkRepoPath = rel: config.lib.file.mkOutOfStoreSymlink "${cfg.repoRoot}/${rel}";
in
{
  _module.args.publicDotfilesDelivery = rec {
    mkRepoFile = rel: {
      source = mkRepoPath rel;
    };

    mkRepoTree = rel: {
      source = mkRepoPath rel;
      force = true;
    };

    mkGeneratedText = text: {
      inherit text;
    };

    mkMutableSeedActivation =
      {
        target,
        targetDir,
        sourceRel,
        legacyStorePatterns ? [ ],
        after ? [ "linkGeneration" ],
        mode ? "600",
        nonWritableMessage ? "warning: ${target} is not writable",
      }:
      lib.hm.dag.entryAfter after ''
        target=${lib.escapeShellArg target}
        seed=0

        if [ -L "$target" ]; then
          link_target="$(readlink "$target" 2>/dev/null || true)"
          case "$link_target" in
${lib.concatStringsSep "\n" (map (pattern: "            ${pattern})\n              seed=1\n              ;;") legacyStorePatterns)}
          esac
        elif [ ! -e "$target" ]; then
          seed=1
        fi

        if [ "$seed" -eq 1 ]; then
          $DRY_RUN_CMD rm -f "$target"
          $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg targetDir}
          $DRY_RUN_CMD install -m ${mode} ${mkStorePath sourceRel} "$target"
        elif [ ! -w "$target" ]; then
          echo ${lib.escapeShellArg nonWritableMessage} >&2
        fi
      '';

    # Writable app settings whose declared keys still follow the repo: each
    # apply three-way merges the declaration into the live file (see
    # scripts/merge-settings.jq) and records it as the next merge base.
    mkMergedSettingsActivation =
      {
        target,
        targetDir,
        sourceRel,
        baseName,
        legacyStorePatterns ? [ ],
        after ? [ "linkGeneration" ],
      }:
      lib.hm.dag.entryAfter after ''
        target=${lib.escapeShellArg target}
        declared=${mkStorePath sourceRel}
        base=${lib.escapeShellArg "${config.xdg.stateHome}/public-dotfiles/settings-base/${baseName}"}
        if [ -L "$target" ]; then
          case "$(readlink "$target" 2>/dev/null || true)" in
${lib.concatStringsSep "\n" (map (pattern: "            ${pattern}) $DRY_RUN_CMD rm -f \"$target\" ;;") legacyStorePatterns)}
          esac
        fi
        merged="$(mktemp)"
        if [ ! -e "$target" ]; then
          cp "$declared" "$merged"
        elif ! ${lib.getExe pkgs.jq} --slurpfile base "$([ -f "$base" ] && echo "$base" || echo /dev/null)" \
            --slurpfile declared "$declared" -f ${mkStorePath "scripts/merge-settings.jq"} "$target" >"$merged"; then
          echo "warning: $target is not mergeable JSON; left unchanged" >&2
          rm -f "$merged"
          merged=""
        fi
        if [ -n "$merged" ]; then
          if ! cmp -s "$merged" "$target"; then
            $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg targetDir}
            $DRY_RUN_CMD install -m 600 "$merged" "$target"
          fi
          $DRY_RUN_CMD mkdir -p "$(dirname "$base")"
          $DRY_RUN_CMD install -m 600 "$declared" "$base"
          rm -f "$merged"
        fi
      '';
  };
}
