{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
  home = config.home.homeDirectory;
  # One tool per mirror: `push` (guarded, never prompts) and `drill` (restore proof).
  tool = name: m: pkgs.writeShellApplication {
    name = "encrypted-mirror-${name}";
    runtimeInputs = [ pkgs.git pkgs."git-remote-gcrypt" pkgs.gnupg pkgs.gawk pkgs.coreutils ];
    text = ''
      repo=${lib.escapeShellArg m.repository}
      remote=${lib.escapeShellArg m.remote}
      key=${lib.escapeShellArg m.gpgKey}
      notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"encrypted mirror ${name}\"" >/dev/null 2>&1 || true; }
      # Ready when gpg-agent already holds the passphrase (or the key has none).
      ready() {
        local grip
        for grip in $(gpg --batch --with-colons --with-keygrip -K "$key" | awk -F: '$1=="grp"{print $10}'); do
          gpg-connect-agent "keyinfo $grip" /bye | awk '$2=="KEYINFO"{ if ($7!="1" && $8!="C") bad=1 } END{exit bad}' || return 1
        done
      }
      # Outcome file read by `task doctor`; silence past `expires` is a finding.
      record() {
        local dir="$HOME/.local/state/public-dotfiles/jobs" now; now="$(date +%s)"
        mkdir -p "$dir"
        printf '{"ok":%s,"at":%s,"expires":%s,"detail":"%s"}\n' "$2" "$now" "$((now + $3))" "$4" > "$dir/encrypted-mirror-${name}$1.json"
      }
      mirror() { git -C "$repo" -c gcrypt.participants="$key" -c gcrypt.gpg-args=--pinentry-mode=error "$@"; }
      case "''${1:-push}" in
        push)
          ready || { record "" false ${toString (2 * 86400)} "gpg-agent does not hold the key"; notify "gpg-agent does not hold the key; unlock it once (e.g. sign anything)"; exit 0; }
          if ! { mirror push "gcrypt::$remote" --all && mirror push "gcrypt::$remote" --tags; }; then record "" false ${toString (2 * 86400)} "push failed"; notify "push failed"; exit 1; fi
          record "" true ${toString (2 * 86400)} "pushed" ;;
        drill)
          scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
          git -c gcrypt.gpg-args=--pinentry-mode=error clone --quiet --mirror "gcrypt::$remote" "$scratch/mirror"
          want="$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"
          got="$(git -C "$scratch/mirror" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"
          [ "$want" = "$got" ] || { echo "ref mismatch" >&2; diff <(echo "$want") <(echo "$got") >&2 || true; exit 1; }
          head_files() { git -C "$1" ls-tree -r --name-only HEAD | wc -l; }
          [ "$(head_files "$repo")" = "$(head_files "$scratch/mirror")" ] || { echo "file count mismatch" >&2; exit 1; }
          record -drill true 2592000 "$(echo "$want" | wc -l) refs matched"
          echo "restore drill matched: $(echo "$want" | wc -l) refs, $(head_files "$repo") files at HEAD" ;;
        *) echo "usage: encrypted-mirror-${name} [push|drill]" >&2; exit 2 ;;
      esac
    '';
  };
in {
  options.xj.publicDotfiles.encryptedMirrors = lib.mkOption {
    default = { };
    description = "Daily encrypted off-machine mirrors of git repositories (git-remote-gcrypt). The remote and key id are downstream data.";
    type = lib.types.attrsOf (lib.types.submodule { options = {
      repository = lib.mkOption { type = lib.types.strMatching "/.*"; description = "Local repository whose commits (never the working tree) are mirrored."; };
      remote = lib.mkOption { type = lib.types.str; description = "git-remote-gcrypt backend URL or path, without the gcrypt:: prefix."; };
      gpgKey = lib.mkOption { type = lib.types.str; description = "GPG key id the whole repository is encrypted to."; };
      interval = lib.mkOption { type = lib.types.ints.positive; default = 86400; };
    }; });
  };
  config = lib.mkIf (cfg.enable && cfg.encryptedMirrors != { }) {
    home.packages = lib.mapAttrsToList (name: m: tool name m) cfg.encryptedMirrors;
    launchd.agents = lib.mkIf pkgs.stdenv.isDarwin (lib.mapAttrs' (name: m: lib.nameValuePair "encrypted-mirror-${name}" {
      enable = true;
      config = {
        ProgramArguments = [ "${tool name m}/bin/encrypted-mirror-${name}" "push" ];
        StartInterval = m.interval;
        ProcessType = "Background";
        LowPriorityIO = true;
        EnvironmentVariables.PATH = "${home}/.local/state/nix/profiles/home-manager/home-path/bin:/usr/bin:/bin";
      };
    }) cfg.encryptedMirrors);
  };
}
