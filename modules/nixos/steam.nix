{
  # Steam, through the NixOS module rather than a bare package: it adds the
  # 32-bit Mesa drivers (hardware.graphics.enable32Bit) and the udev rules for
  # Steam's controllers, which games and Big Picture need.
  programs.steam.enable = true;
}
