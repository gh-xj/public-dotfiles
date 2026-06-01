{ ... }:

{
  xj.publicDotfiles = {
    enable = true;
    repoRoot = "/Users/example/public-dotfiles";
  };

  home = {
    username = "example";
    homeDirectory = "/Users/example";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
