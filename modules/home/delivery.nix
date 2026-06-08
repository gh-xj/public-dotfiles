{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles;
  repoRootPath = ../..;
  mkStorePath = rel: repoRootPath + "/${rel}";
  mkRepoPath = rel: config.lib.file.mkOutOfStoreSymlink "${cfg.repoRoot}/${rel}";
in
{
  _module.args.publicDotfilesDelivery = rec {
    mkImmutableFile = rel: {
      source = mkStorePath rel;
    };

    mkImmutableTree = rel: {
      source = mkStorePath rel;
      force = true;
    };

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
  };
}
