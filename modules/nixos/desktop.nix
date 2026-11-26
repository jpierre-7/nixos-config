{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Niri session, portals (GNOME + GTK), polkit and dconf come from this module.
  programs.niri.enable = true;

  # Polkit authentication agent. The niri module runs polkitd but no agent,
  # so GUI actions that need the admin password failed with no prompt; e.g.
  # Nautilus showed "Operation was cancelled" when mounting the external SSDs
  # through udisks (external-drives.nix). Runs as a user service under
  # graphical-session.target.
  security.soteria.enable = true;

  environment.systemPackages = with pkgs; [
    # Niri starts this on demand for X11 apps (ONLYOFFICE, AnyDesk); it only
    # has to be on PATH. The niri module doesn't install it.
    xwayland-satellite
    xdg-utils
  ];

  # Vicinae reads the app list only when its server starts, so an app a rebuild
  # added (Steam) stayed out of the launcher until the next login. Restart it
  # on every switch: user activation runs then, as john, with NIRI_SOCKET from
  # the user manager. Through niri, so the new server stays in niri's session
  # like the one spawn-at-startup started (config/niri/config.kdl).
  system.userActivationScripts.restartVicinae.text = ''
    if [ -n "''${NIRI_SOCKET:-}" ] && ${pkgs.procps}/bin/pgrep -u "$(id -u)" -f "^vicinae-server" >/dev/null; then
      ${lib.getExe config.programs.niri.package} msg action spawn -- vicinae server --replace || true
    fi
  '';

  # Unlock the login keyring with the password typed at the greeter
  # (greeter.nix).
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Trash, removable drives and network locations in Nautilus.
  services.gvfs.enable = true;

  # Mesa OpenGL/Vulkan for AMD and Intel GPUs. Steam (steam.nix) adds the
  # 32-bit drivers its games need.
  hardware.graphics.enable = true;

  # Fullscreen recording in Noctalia's Screen Toolkit plugin
  # (modules/home/noctalia.nix). The module adds the capability wrapper
  # gpu-screen-recorder needs to capture a monitor without the portal prompt.
  programs.gpu-screen-recorder.enable = true;

  # Noctalia's battery and power-profile widgets need these (see its NixOS docs).
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  # Run Electron/Chromium apps (Vesktop, Slack, Teams, VS Code, Signal) as native
  # Wayland clients instead of through XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
