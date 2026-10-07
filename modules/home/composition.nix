{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
  yaml = pkgs.formats.yaml { };
  defaults = builtins.fromJSON (builtins.readFile ../../.config/workmux/config.yaml);
  agentType = lib.types.submodule {
    options = {
      argv = lib.mkOption { type = lib.types.nonEmptyListOf lib.types.str; description = "Executable and arguments; serialized with shell-safe quoting for Workmux."; };
      type = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Workmux public agent type used for wrapper detection."; };
    };
  };
  agents = lib.mapAttrs (_: entry: { command = lib.escapeShellArgs entry.argv; }
    // lib.optionalAttrs (entry.type != null) { type = entry.type; }) cfg.workmux.extraAgents;
in {
  options.xj.publicDotfiles = {
    workmux.agent = lib.mkOption { type = lib.types.str; default = defaults.agent; };
    workmux.extraAgents = lib.mkOption { type = lib.types.attrsOf agentType; default = { }; };
    workmux.extraConfig = lib.mkOption { type = yaml.type; default = { }; description = "Additional Workmux settings; the public agent selection and status_format=false remain authoritative."; };
    scratchGc.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Deliver a downstream-owned scratch collector package through the public ownership boundary."; };
    scratchGc.package = lib.mkOption { type = lib.types.nullOr lib.types.package; default = null; description = "Complete downstream scratch-gc package; no public implementation is assumed."; };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      xdg.configFile."workmux/config.yaml".source = yaml.generate "workmux-config.yaml"
        (defaults // cfg.workmux.extraConfig // { agent = cfg.workmux.agent; status_format = false; inherit agents; });
      assertions = [{ assertion = !cfg.scratchGc.enable || cfg.scratchGc.package != null;
        message = "scratchGc.enable requires a complete downstream package; otherwise leave public ownership disabled."; }];
    }
    (lib.mkIf cfg.scratchGc.enable {
      home.packages = [ cfg.scratchGc.package ];
      home.file.".local/bin/scratch-gc".source = "${cfg.scratchGc.package}/bin/scratch-gc";
    })
  ]);
}
