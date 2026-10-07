{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles.tmuxRecovery;
  engine = pkgs.writeShellApplication {
    name = "tmux-recovery";
    runtimeInputs = [ pkgs.python3 pkgs.tmux pkgs.neovim ];
    text = ''
      exec python3 ${../../scripts/tmux-recovery.py} \
        --output-directory ${lib.escapeShellArg cfg.outputDirectory} \
        --keep-newest ${toString cfg.keepNewest} --keep-days ${toString cfg.keepDays} \
        ${lib.optionalString (cfg.adaptersFile != null) "--adapters ${lib.escapeShellArg cfg.adaptersFile}"} "$@"
    '';
  };
in {
  options.xj.publicDotfiles.tmuxRecovery = {
    enable = lib.mkEnableOption "tmux topology recovery engine";
    outputDirectory = lib.mkOption { type = lib.types.strMatching "/.*"; default = "${config.home.homeDirectory}/.local/state/tmux-agents-recovery"; };
    keepNewest = lib.mkOption { type = lib.types.ints.positive; default = 32; description = "Global cap on owned snapshots, including the current protected snapshot."; };
    keepDays = lib.mkOption { type = lib.types.ints.positive; default = 7; };
    adaptersFile = lib.mkOption { type = lib.types.nullOr (lib.types.strMatching "/.*"); default = null; description = "Trusted local JSON/TOML provider map; not copied into checkpoints."; };
    schedule.enable = lib.mkEnableOption "periodic checkpoint-all through launchd";
    schedule.interval = lib.mkOption { type = lib.types.ints.positive; default = 300; description = "Checkpoint interval in seconds."; };
  };
  config = lib.mkIf (config.xj.publicDotfiles.enable && cfg.enable) {
    home.packages = [ engine ];
    home.file.".local/bin/tmux-recovery".source = "${engine}/bin/tmux-recovery";
    launchd.agents.tmux-recovery = lib.mkIf (pkgs.stdenv.isDarwin && cfg.schedule.enable) {
      enable = true;
      config = {
        ProgramArguments = [ "${config.home.homeDirectory}/.local/bin/tmux-recovery" "checkpoint-all" ];
        StartInterval = cfg.schedule.interval;
        RunAtLoad = true;
        ProcessType = "Background";
        Umask = 63;
      };
    };
  };
}
