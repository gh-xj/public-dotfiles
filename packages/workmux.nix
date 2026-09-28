{ fetchFromGitHub, git, installShellFiles, lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "workmux";
  version = "0.1.248";

  src = fetchFromGitHub {
    owner = "raine";
    repo = "workmux";
    rev = "v${version}";
    hash = "sha256-qubWyOxzzODezZjNtQT71NmrFP7xoEGhMjbw/2QZnQk=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "crossterm-0.29.0" = "sha256-rfAaqGylDaxx3bjmofifnzSh7Hmh21BzHp5fS/w2Z6I=";
    };
  };

  nativeBuildInputs = [
    git
    installShellFiles
  ];

  postInstall = ''
    export HOME="$TMPDIR"
    installShellCompletion --cmd workmux \
      --bash <($out/bin/workmux completions bash) \
      --fish <($out/bin/workmux completions fish) \
      --zsh <($out/bin/workmux completions zsh)
  '';

  meta = {
    description = "Git worktree and terminal multiplexer workflow for parallel development";
    homepage = "https://github.com/raine/workmux";
    license = lib.licenses.mit;
    mainProgram = "workmux";
  };
}
