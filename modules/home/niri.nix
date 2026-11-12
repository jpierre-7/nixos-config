{ pkgs, ... }:
{
  # Niri itself is installed by the NixOS module (modules/nixos/desktop.nix).
  # It reloads this file when a rebuild swaps the link. The per-host outputs
  # file (host.kdl) is linked from hosts/<host>/default.nix.
  xdg.configFile."niri/config.kdl".source = ../../config/niri/config.kdl;

  # Mod+Shift+0 in config.kdl. Niri's move-window-to-monitor has no focus=false
  # (move-window-to-workspace does), so move the window, then focus the monitor
  # it came from. A monitor that isn't connected makes both steps no-ops.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "niri-send-window";
      runtimeInputs = [
        pkgs.niri
        pkgs.jq
      ];
      text = ''
        from=$(niri msg --json focused-output | jq -r .name)
        niri msg action move-window-to-monitor "$1"
        niri msg action focus-monitor "$from"
      '';
    })
  ];

  # Installs the theme into ~/.icons and ~/.local/share/icons and sets it for
  # GTK and X11 apps. Niri draws its own cursor and exports XCURSOR_* to the
  # apps it spawns from the `cursor` block in config.kdl; keep the name and
  # size there in sync with these.
  home.pointerCursor = {
    package = pkgs.comixcursors.Opaque_Blue;
    name = "ComixCursors-Opaque-Blue";
    # Smallest size the theme ships (32/40/48/64); 24 would just be rounded up.
    size = 32;
    gtk.enable = true;
    x11.enable = true;
  };
}
