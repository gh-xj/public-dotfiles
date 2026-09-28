{ config, lib, pkgs, ... }:
let
  recovery = pkgs.writeShellApplication {
    name = "tmux-recovery";
    runtimeInputs = [ pkgs.python3 pkgs.tmux ];
    text = ''exec python3 ${../../scripts/tmux-recovery.py} "$@"'';
  };
  scratch = pkgs.writeShellApplication {
    name = "scratch-gc";
    runtimeInputs = [ pkgs.python3 ];
    text = ''exec python3 ${../../scripts/scratch-gc.py} "$@"'';
  };
in {
  config = lib.mkIf config.xj.publicDotfiles.enable {
    home.packages = [ recovery scratch ];
    home.file.".local/bin/tmux-recovery".source = "${recovery}/bin/tmux-recovery";
    home.file.".local/bin/scratch-gc".source = "${scratch}/bin/scratch-gc";
  };
}
