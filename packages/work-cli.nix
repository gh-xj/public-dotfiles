{ buildGoModule, fetchFromGitHub, lib }:

buildGoModule rec {
  pname = "work-cli";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "gh-xj";
    repo = "work-cli";
    rev = "v${version}";
    hash = "sha256-PGAwD4kcBx1nypI6UFiSkVKkU1mBCoB1Z7dLzhxemzM=";
  };

  vendorHash = "sha256-97TzBn+JtSjCkA0CORFE8Rb8OGKg7qBJsEFEnBut8Kk=";

  subPackages = [ "cmd/work" ];
  ldflags = [
    "-s"
    "-w"
    "-X github.com/gh-xj/work-cli/internal/workcli.appVersion=v${version}"
  ];

  meta = {
    description = "Local-first work tracker CLI for repo-local .work stores";
    homepage = "https://github.com/gh-xj/work-cli";
    license = lib.licenses.mit;
    mainProgram = "work";
  };
}
