# bind-palette: Mod+Slash (config/niri/config.kdl) searches every keybind in one
# Vicinae list. Script: pkgs/bind-palette/. qutebrowser feeds it through
# config/qutebrowser/bindsdump.py (modules/home/qutebrowser.nix).
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ../../pkgs/bind-palette { kanataKeymap = ../../config/kanata/keymap.kbd; })
  ];
}
