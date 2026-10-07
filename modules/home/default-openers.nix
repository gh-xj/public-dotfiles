{ config, lib, publicDotfilesDelivery, ... }:

let
  cfg = config.xj.publicDotfiles;
  policy = ../../config/macos/default-openers.duti;
in
{
  config = lib.mkIf cfg.enable {
    xdg.configFile."public-dotfiles/default-openers.duti" = publicDotfilesDelivery.mkRepoFile "config/macos/default-openers.duti";
    home.activation.defaultOpeners = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      duti_bin=""
      for candidate in /opt/homebrew/bin/duti /usr/local/bin/duti; do
        if [ -x "$candidate" ]; then
          duti_bin="$candidate"
          break
        fi
      done
      if [ -n "$duti_bin" ]; then
        $DRY_RUN_CMD "$duti_bin" ${policy}
      else
        echo "Homebrew duti is not installed; run task apps, then re-run task apply" >&2
      fi
    '';
  };
}
