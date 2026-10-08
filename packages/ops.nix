pkgs: [
  pkgs.awscli2
  pkgs.cloudflared
  pkgs.exiftool
  pkgs.ffmpeg
  pkgs.gh
  pkgs.gitleaks
  pkgs.pandoc
  pkgs."poppler-utils"
  pkgs.rclone
  pkgs."ripgrep-all"
  pkgs."whisper-cpp"
  (pkgs.callPackage ./work-cli.nix { })
]
