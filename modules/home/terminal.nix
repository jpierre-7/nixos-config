{
  # Colors come from Noctalia's palette (the wezterm template in noctalia.nix).
  programs.wezterm = {
    enable = true;
    extraConfig = builtins.readFile ../../config/wezterm/wezterm.lua;
  };

  # wezterm.lua does `require("keys")`.
  xdg.configFile."wezterm/keys.lua".source = ../../config/wezterm/keys.lua;
}
