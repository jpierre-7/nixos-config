{ pkgs, ... }:
{
  # Niri session, portals (GNOME + GTK), polkit and dconf come from this module.
  programs.niri.enable = true;

  environment.systemPackages = with pkgs; [
    # Niri starts this on demand for X11 apps (ONLYOFFICE, AnyDesk); it only
    # has to be on PATH. The niri module doesn't install it.
    xwayland-satellite
    xdg-utils
  ];

  # Login screen, as on Arch. Runs on greetd.
  services.displayManager.cosmic-greeter.enable = true;

  # Unlock the login keyring with the password typed at the greeter.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Trash, removable drives and network locations in Nautilus.
  services.gvfs.enable = true;

  # Mesa OpenGL/Vulkan. Enough for AMD and Intel GPUs on a non-gaming setup.
  hardware.graphics.enable = true;

  # Noctalia's battery and power-profile widgets need these (see its NixOS docs).
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  # Run Electron/Chromium apps (Vesktop, Slack, VS Code, Signal) as native
  # Wayland clients instead of through XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
