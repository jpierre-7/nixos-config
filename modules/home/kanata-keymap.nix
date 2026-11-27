# Kanata keymap viewer. Mod+Ctrl+Slash (config/niri/config.kdl) toggles a
# keymap-drawer render of config/kanata/keymap.kbd in a bare qutebrowser window.
# Number keys switch layers, / searches every layer. A path unit redraws it on
# every save in the checkout, so it can be ahead of the running kanata, which
# loads the store copy (modules/nixos/kanata.nix). Script: pkgs/kanata-keymap/.
# Colors: Noctalia's kanata-keymap template (modules/home/noctalia.nix).
# Adapted from HefKer/nixos-config's homes/modules/kanata-keymap.nix.
{
  lib,
  pkgs,
  repoDir,
  ...
}:
let
  keymap = pkgs.callPackage ../../pkgs/kanata-keymap { };
  keymapDir = "${repoDir}/config/kanata";
in
{
  home.packages = [ keymap ];

  systemd.user.services.kanata-keymap-render = {
    Unit.Description = "Draw the kanata keymap for the keymap viewer";
    Service = {
      Type = "oneshot";
      ExecStart = lib.escapeShellArgs [
        (lib.getExe' keymap "kanata-keymap-render")
        keymapDir
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.paths.kanata-keymap-render = {
    Unit.Description = "Redraw the kanata keymap when it changes";
    Path.PathChanged = [
      "${keymapDir}/keymap.kbd"
      "${keymapDir}/keymap-drawer.yaml"
    ];
    Install.WantedBy = [ "default.target" ];
  };
}
