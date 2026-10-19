# tmux 3.6a corrupts the heap when a sixel image is freed from saved_images
# (CVE-2026-11623, fixed in 3.6b); that crashed a 26-day server in copy-mode.
# Build 3.6b until nixpkgs ships it; this drops out once nixpkgs moves on.
pkgs:
if pkgs.tmux.version == "3.6a" then
  pkgs.tmux.overrideAttrs (old: rec {
    version = "3.6b";
    src = pkgs.fetchFromGitHub {
      owner = "tmux";
      repo = "tmux";
      tag = version;
      hash = "sha256-iW4K/OxSVpxVkyI5Dy6lzwVf/8nXyjcHtL76Ezmxavc=";
    };
  })
else
  pkgs.tmux
