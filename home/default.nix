let
  username = "john";
  homePath = "/home/${username}";
  flakePath = "${homePath}/nixos";
in
{
  imports = [];

  home = {
    inherit username;
    homeDirectory = homePath;
    stateVersion = "25.11";

    # Maps each config folder into ~/.config/<name>
    file = {
      ".config/fastfetch".source = ./config/fastfetch;
      ".config/fish".source     = ./config/fish;
      ".config/lsd".source      = ./config/lsd;
      ".config/niri".source     = ./config/niri;
      ".config/noctalia".source = ./config/noctalia;
      ".config/vicinae".source  = ./config/vicinae;
      ".config/wezterm".source  = ./config/wezterm;
    };
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
