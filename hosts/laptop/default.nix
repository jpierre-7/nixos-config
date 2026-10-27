# Laptop. Everything shared lives in modules/; only machine-specific bits go here.
#
# - Monitors: no host.kdl, so niri configures the built-in panel automatically.
#   Add a niri-outputs.kdl like the desktop's if you want a fixed scale/mode.
# - Power: battery and power profiles come from UPower and power-profiles-daemon
#   (shared, because Noctalia's widgets use them on both machines). Closing the
#   lid suspends by default.
# - Graphics: Mesa (shared). See the README if this machine needs NVIDIA's driver.
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Release this machine was first installed with. Leave it alone on upgrades
  # (see the README); it is not the NixOS version you are running.
  system.stateVersion = "26.05";
}
