pkgs: [
  pkgs.awscli2
  pkgs.clamav
  pkgs.cloudflared
  pkgs.exiftool
  pkgs.ffmpeg
  pkgs.gh
  pkgs.gitleaks
  pkgs.imagemagick
  pkgs.pandoc
  pkgs."poppler-utils"
  pkgs.rclone
  pkgs."ripgrep-all"
  pkgs.wget
  pkgs."whisper-cpp"
  (pkgs.callPackage ./work-cli.nix { })
]
