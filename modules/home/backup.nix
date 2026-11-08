{ config, lib, pkgs, ... }:
let
  cfg = config.xj.publicDotfiles;
  home = config.home.homeDirectory;
  # One tool per mirror: `push` (guarded, never prompts) and `drill` (restore proof).
  tool = name: m:
  let
    remoteName = if m.remoteName == null then name else m.remoteName;
  in pkgs.writeShellApplication {
    name = "encrypted-mirror-${name}";
    runtimeInputs = [ pkgs.git pkgs."git-remote-gcrypt" pkgs.gnupg pkgs.gawk pkgs.coreutils ];
    text = ''
      repo=${lib.escapeShellArg m.repository}
      remote_name=${lib.escapeShellArg remoteName}
      remote_url=${lib.escapeShellArg "gcrypt::${m.remote}"}
      key=${lib.escapeShellArg m.gpgKey}
      signing_key=${lib.escapeShellArg m.signingKey}
      namespace=${lib.escapeShellArg "refs/encrypted-mirrors/${name}"}
      notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"encrypted mirror ${name}\"" >/dev/null 2>&1 || true; }
      # Ready when gcrypt's own steps, signing and decrypting, work without a prompt. keyinfo
      # flags are not enough: gpg-agent unlocks a subkey with the last passphrase entered
      # without caching it under that subkey's keygrip, so a usable key reads as locked.
      ready() {
        gpg --batch --quiet --pinentry-mode error --local-user "$signing_key" --sign </dev/null >/dev/null 2>&1 &&
          gpg --batch --quiet --trust-model always --encrypt --recipient "$key" </dev/null 2>/dev/null |
          gpg --batch --quiet --pinentry-mode error --decrypt >/dev/null 2>&1
      }
      # Was the last recorded run a failure? An operator who learned to ignore this job
      # needs the first recovery to announce itself.
      was_failing() { grep -q '"ok":false' "$HOME/.local/state/public-dotfiles/jobs/encrypted-mirror-${name}.json" 2>/dev/null; }
      # Outcome file read by `task doctor`; silence past `expires` is a finding.
      record() {
        local dir="$HOME/.local/state/public-dotfiles/jobs" now; now="$(date +%s)"
        mkdir -p "$dir"
        printf '{"ok":%s,"at":%s,"expires":%s,"detail":"%s"}\n' "$2" "$now" "$((now + $3))" "$4" > "$dir/encrypted-mirror-${name}$1.json"
      }
      mirror() {
        git -C "$repo" \
          -c gcrypt.participants="$key" \
          -c gcrypt.signingkey="$signing_key" \
          -c gcrypt.publish-participants=false \
          -c gcrypt.require-explicit-force-push=true \
          -c gcrypt.gpg-args=--pinentry-mode=error "$@"
      }
      fail() { record "" false ${toString (2 * 86400)} "$1"; notify "$1"; echo "$1" >&2; exit 1; }
      verify_remote() {
        local configured recorded_id
        configured="$(git -C "$repo" remote get-url --push "$remote_name" 2>/dev/null)" || return 1
        [ "$configured" = "$remote_url" ] || return 1
        recorded_id="$(git -C "$repo" config --get "remote.$remote_name.gcrypt-id" 2>/dev/null)"
        [ -n "$recorded_id" ]
      }
      fetch_remote() {
        mirror fetch --quiet --no-tags --no-write-fetch-head --prune "$remote_name" \
          "+refs/heads/*:$namespace/heads/*" \
          "+refs/tags/*:$namespace/tags/*"
      }
      guard_divergence() {
        local remote_ref remote_oid branch local_ref local_oid tag
        while read -r remote_ref remote_oid; do
          [ -n "$remote_ref" ] || continue
          branch="''${remote_ref#"$namespace/heads/"}"
          local_ref="refs/heads/$branch"
          local_oid="$(git -C "$repo" rev-parse --verify "$local_ref" 2>/dev/null)" || {
            echo "mirror branch has no local counterpart: $branch" >&2
            return 1
          }
          git -C "$repo" merge-base --is-ancestor "$remote_oid" "$local_oid" || {
            echo "local branch does not fast-forward mirror branch: $branch" >&2
            return 1
          }
        done < <(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' "$namespace/heads")
        while read -r remote_ref remote_oid; do
          [ -n "$remote_ref" ] || continue
          tag="''${remote_ref#"$namespace/tags/"}"
          local_oid="$(git -C "$repo" rev-parse --verify "refs/tags/$tag" 2>/dev/null)" || {
            echo "mirror tag has no local counterpart: $tag" >&2
            return 1
          }
          [ "$local_oid" = "$remote_oid" ] || {
            echo "local and mirror tag differ: $tag" >&2
            return 1
          }
        done < <(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' "$namespace/tags")
      }
      verify_pushed() {
        local local_ref local_oid branch remote_oid tag
        while read -r local_ref local_oid; do
          branch="''${local_ref#refs/heads/}"
          remote_oid="$(git -C "$repo" rev-parse --verify "$namespace/heads/$branch" 2>/dev/null)" || return 1
          [ "$local_oid" = "$remote_oid" ] || return 1
        done < <(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' refs/heads)
        while read -r local_ref local_oid; do
          tag="''${local_ref#refs/tags/}"
          remote_oid="$(git -C "$repo" rev-parse --verify "$namespace/tags/$tag" 2>/dev/null)" || return 1
          [ "$local_oid" = "$remote_oid" ] || return 1
        done < <(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' refs/tags)
      }
      case "''${1:-push}" in
        push)
          recovering=false; if was_failing; then recovering=true; fi
          ready || fail "gpg-agent does not hold the key; unlock it once (e.g. sign anything)"
          verify_remote || fail "named remote is missing, has the wrong URL, or lacks its recorded gcrypt-id"
          fetch_remote || fail "mirror fetch failed"
          guard_divergence || fail "mirror diverged; refusing destructive gcrypt force-push"
          if ! { mirror push --force "$remote_name" --all && mirror push --force "$remote_name" --tags; }; then fail "push failed"; fi
          fetch_remote || fail "post-push mirror fetch failed"
          verify_pushed || fail "post-push refs do not match"
          record "" true ${toString (2 * 86400)} "pushed"
          if [ "$recovering" = true ]; then notify "push recovered; the mirror is current again"; fi ;;
        drill)
          verify_remote || { echo "named remote is missing, has the wrong URL, or lacks its recorded gcrypt-id" >&2; exit 1; }
          scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
          recorded_id="$(git -C "$repo" config --get "remote.$remote_name.gcrypt-id")"
          git init --quiet --bare "$scratch/mirror"
          git -C "$scratch/mirror" remote add origin "$remote_url"
          git -C "$scratch/mirror" config remote.origin.gcrypt-id "$recorded_id"
          git -C "$scratch/mirror" \
            -c gcrypt.participants="$key" \
            -c gcrypt.signingkey="$signing_key" \
            -c gcrypt.publish-participants=false \
            -c gcrypt.gpg-args=--pinentry-mode=error \
            fetch --quiet --no-tags origin "+refs/heads/*:refs/heads/*" "+refs/tags/*:refs/tags/*"
          want="$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"
          got="$(git -C "$scratch/mirror" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"
          [ "$want" = "$got" ] || { echo "ref mismatch" >&2; diff <(echo "$want") <(echo "$got") >&2 || true; exit 1; }
          # The bare mirror's HEAD is the default branch, so name the commit the repo has checked out.
          head="$(git -C "$repo" rev-parse HEAD)"
          git -C "$scratch/mirror" cat-file -e "$head^{commit}" 2>/dev/null || { echo "checked-out commit $head is on no mirrored ref" >&2; exit 1; }
          head_files() { git -C "$1" ls-tree -r --name-only "$head" | wc -l; }
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
    type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: { options = {
      repository = lib.mkOption { type = lib.types.strMatching "/.*"; description = "Local repository whose commits (never the working tree) are mirrored."; };
      remote = lib.mkOption { type = lib.types.str; description = "git-remote-gcrypt backend URL or path, without the gcrypt:: prefix."; };
      remoteName = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Existing named remote carrying the recorded gcrypt-id; defaults to the encryptedMirrors attribute name."; };
      gpgKey = lib.mkOption { type = lib.types.str; description = "GPG key id the whole repository is encrypted to."; };
      signingKey = lib.mkOption { type = lib.types.str; default = config.gpgKey; description = "GPG key used to sign the encrypted manifest; defaults to gpgKey."; };
      interval = lib.mkOption { type = lib.types.ints.positive; default = 86400; };
    }; }));
  };
  config = lib.mkIf (cfg.enable && cfg.encryptedMirrors != { }) {
    home.packages = lib.mapAttrsToList (name: m: tool name m) cfg.encryptedMirrors
      ++ lib.optional pkgs.stdenv.isDarwin pkgs.pinentry_mac;
    # The mirror's "unlock it once" needs a pinentry, and gpg-agent has no default. Seed the conf
    # rather than own it: a hand-written one must neither be replaced nor fail activation. The
    # profile path outlives a store path, and gpg-agent wants ~/.gnupg private.
    home.activation.encryptedMirrorPinentry = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e "$HOME/.gnupg/gpg-agent.conf" ]; then
        run mkdir -p -m 700 "$HOME/.gnupg"
        run ${pkgs.bash}/bin/bash -c 'echo "pinentry-program $1" > "$2"' _ ${lib.escapeShellArg "${home}/.local/state/nix/profiles/home-manager/home-path/bin/pinentry-mac"} "$HOME/.gnupg/gpg-agent.conf"
        run ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
      fi
    '');
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
