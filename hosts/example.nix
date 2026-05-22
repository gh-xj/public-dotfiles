{ ... }:

{
  xj.publicDotfiles.enable = true;

  home = {
    username = "example";
    homeDirectory = "/Users/example";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
