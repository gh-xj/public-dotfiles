{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
  rt = cfg.retention;
  home = config.home.homeDirectory;
  settings = pkgs.writeText "retention.json" (builtins.toJSON {
    logs = { globs = rt.logs.globs; maxBytes = rt.logs.maxMegabytes * 1048576; };
    archiveDirectory = rt.archiveDirectory;
    archives = lib.mapAttrsToList (name: spec: spec // { inherit name; }) rt.archives;
    # A downstream scratch collector (scratchGc) replaces the built-in scratch pass.
    scratch = lib.optionals (!cfg.scratchGc.enable) (lib.attrValues rt.scratch);
  });
  engine = pkgs.writeShellApplication {
    name = "workstation-retention";
    runtimeInputs = [ pkgs.python3 pkgs.gnutar pkgs.zstd ];
    text = ''exec python3 ${../../scripts/retention.py} ${settings} --status-directory ${home}/.local/state/public-dotfiles/jobs ${lib.optionalString rt.apply "--apply"} "$@"'';
  };
in {
  options.xj.publicDotfiles.retention = {
    enable = lib.mkEnableOption "bounded growth for agent transcripts, launchd logs and scratch space";
    apply = lib.mkOption { type = lib.types.bool; default = false; description = "Scheduled runs only report until this is true; `workstation-retention --apply` always applies."; };
    interval = lib.mkOption { type = lib.types.ints.positive; default = 86400; description = "Seconds between scheduled runs."; };
    logs.globs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "${home}/Library/Logs/*.log" "${home}/.local/state/*.log" "${home}/.local/state/*/*.log" ]; description = "Log files truncated in place, keeping their newest lines."; };
    logs.maxMegabytes = lib.mkOption { type = lib.types.ints.positive; default = 100; };
    archiveDirectory = lib.mkOption { type = lib.types.str; default = "${home}/.local/state/public-dotfiles/archive"; };
    archives = lib.mkOption {
      default = { };
      description = "Transcript trees archived per day as verified tar.zst; originals are removed only after verification.";
      type = lib.types.attrsOf (lib.types.submodule { options = {
        root = lib.mkOption { type = lib.types.str; };
        glob = lib.mkOption { type = lib.types.str; };
        keepDays = lib.mkOption { type = lib.types.ints.positive; default = 30; };
      }; });
    };
    scratch = lib.mkOption {
      default = { };
      description = "Scratch roots whose top-level entries are removed once nothing inside was touched for maxAgeDays; {uid} expands.";
      type = lib.types.attrsOf (lib.types.submodule { options = {
        root = lib.mkOption { type = lib.types.str; };
        maxAgeDays = lib.mkOption { type = lib.types.ints.positive; default = 14; };
      }; });
    };
  };
  config = lib.mkIf (cfg.enable && rt.enable) {
    xj.publicDotfiles.retention = {
      archives.codex = { root = lib.mkDefault "${home}/.codex/sessions"; glob = lib.mkDefault "**/*.jsonl"; };
      archives.claude = { root = lib.mkDefault "${home}/.claude/projects"; glob = lib.mkDefault "*/*.jsonl"; };
      scratch.claude = { root = lib.mkDefault "/private/tmp/claude-{uid}"; };
    };
    home.packages = [ engine ];
    home.file.".local/bin/workstation-retention".source = "${engine}/bin/workstation-retention";
    launchd.agents.workstation-retention = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${home}/.local/bin/workstation-retention" ];
        StartInterval = rt.interval;
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 10;
        StandardOutPath = "${home}/Library/Logs/workstation-retention.log";
        StandardErrorPath = "${home}/Library/Logs/workstation-retention.log";
      };
    };
  };
}
