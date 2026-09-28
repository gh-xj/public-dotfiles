#!/usr/bin/env zsh
# Stock-macOS preflight and Home Manager pre-link migration share this engine.
set -euo pipefail

target_home=""
checkout=""
mode=--dry-run
while (( $# )); do
    case "$1" in
        --home|--repo)
            (( $# >= 2 )) || { print -u2 'migration: missing option value'; exit 2; }
            if [[ "$1" == --home ]]; then target_home="$2"; else checkout="$2"; fi
            shift 2
            ;;
        --apply|--dry-run) mode="$1"; shift ;;
        *) print -u2 'usage: migrate-ghostty-parent.zsh --home HOME --repo CHECKOUT [--dry-run|--apply]'; exit 2 ;;
    esac
done
[[ "$target_home" == /* && "$checkout" == /* ]] || {
    print -u2 'migration: --home and --repo must be absolute paths'
    exit 2
}

checkout="${checkout:A}"
parent="$target_home/.config/ghostty"
config_root="${parent:h}"
config_root="${config_root:A}"
legacy="$checkout/.config/ghostty"
legacy="${legacy:A}"

# Even a real ghostty directory is unsafe if an ancestor redirects into Git.
if [[ "$config_root" == "$checkout" || "$config_root" == "$checkout"/* ]]; then
    print -u2 "migration: $target_home/.config resolves inside the checkout; replace that ancestor symlink before applying Home Manager"
    exit 1
fi

# Test the link itself first, including dangling links. Never dereference it
# for mutation, and never recursively remove or move its target directory.
if [[ -L "$parent" ]]; then
    original=$(readlink -- "$parent")
    resolved="$original"
    [[ "$resolved" == /* ]] || resolved="${parent:h}/$resolved"
    resolved="${resolved:A}"
    if [[ "$resolved" != "$legacy" ]]; then
        print -u2 "migration: refusing unknown Ghostty parent symlink: $parent -> $original"
        print -u2 'Inspect and move that symlink aside explicitly, create a real directory, then rerun. Automatic leaf backups do not authorize replacing this parent.'
        exit 1
    fi
    print -r -- "Ghostty migration ($mode): unlink legacy parent $parent -> $original; preserve its target and create a real directory"
    if [[ "$mode" == --apply ]]; then
        [[ -L "$parent" && "$(readlink -- "$parent")" == "$original" ]] || {
            print -u2 'migration: parent changed during inspection; retry after resolving concurrent changes'
            exit 1
        }
        rm -- "$parent"
        mkdir -p -- "$parent"
    fi
elif [[ -e "$parent" ]]; then
    [[ -d "$parent" ]] || {
        print -u2 "migration: $parent is not a directory; move the file aside explicitly before applying"
        exit 1
    }
    # Home Manager owns the leaf and its normal conflict/backup handling.
else
    print -r -- "Ghostty migration ($mode): create real directory $parent"
    if [[ "$mode" == --apply ]]; then mkdir -p -- "$parent"; fi
fi
