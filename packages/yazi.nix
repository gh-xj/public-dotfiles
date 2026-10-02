{ yazi, yazi-unwrapped, fetchFromGitHub, rustPlatform }:

# Keep the tested release without moving the whole nixpkgs baseline.
# Hashes match nixpkgs ffc7769e166a4f48258c53f5eb43f682f40c4315.
let
  version = "26.9.1";
  vendorHash = "sha256-V69VxhMiTY1Tgo4aW06AjwBIoXjK0Ov6oIahxk0NzGg=";
  unwrapped = yazi-unwrapped.overrideAttrs (final: old: {
    inherit version;
    cargoHash = vendorHash;
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (final) pname version srcs sourceRoot;
      hash = final.cargoHash;
    };
    env = old.env // { VERGEN_BUILD_DATE = "2026-09-01"; };
    passthru = old.passthru // {
      srcs = old.passthru.srcs // {
        code_src = fetchFromGitHub {
          owner = "sxyazi";
          repo = "yazi";
          rev = "8dd895c695a5950330c2623eb43debf323b60654";
          hash = "sha256-/8j4bEbT8DR/xlWtt62FXVyeHyWtBlvV8Rq0VbtY6ms=";
        };
      };
    };
    postInstall = old.postInstall + ''
      installShellCompletion --cmd ya \
        --bash ./yazi-cli/completions/ya.bash \
        --fish ./yazi-cli/completions/ya.fish \
        --zsh ./yazi-cli/completions/_ya
    '';
  });
in
 yazi.override { yazi-unwrapped = unwrapped; }
