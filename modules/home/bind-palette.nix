# bind-palette: Mod+Slash (config/niri/config.kdl) searches every keybind in one
# Vicinae list. Script: pkgs/bind-palette/. qutebrowser feeds it through
# config/qutebrowser/bindsdump.py (modules/home/qutebrowser.nix).
{
  config,
  pkgs,
  repoDir,
  ...
}:
{
  home.packages = [
    (pkgs.callPackage ../../pkgs/bind-palette { kanataKeymap = ../../config/kanata/keymap.kbd; })
  ];
  # Live link: the palette's "Hide binds" list appends to it and "Hidden binds" rewrites it.
  xdg.configFile."bind-palette/ignore".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/bind-palette/ignore";
}
