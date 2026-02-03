let
  username = "john";
  homePath = "/home/${username}";
  flakePath = "${homePath}/nixos";
in
{
  imports = [
  ];

  home = {
    inherit username;
    homeDirectory = homePath;
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
  programs.nh = {
    enable = true;
    flake = flakePath;
    clean = {
      enable = true;
      dates = "weekly";
    };
  };
}
