{
  # Niri itself is installed by the NixOS module (modules/nixos/desktop.nix).
  # It reloads this file when a rebuild swaps the link. The per-host outputs
  # file (host.kdl) is linked from hosts/<host>/default.nix.
  xdg.configFile."niri/config.kdl".source = ../../config/niri/config.kdl;
}
