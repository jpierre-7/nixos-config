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

  # Turn the desktop on from anywhere (its side is in hosts/desktop). A magic
  # packet is a LAN broadcast and can't cross the internet, and the desktop's
  # Tailscale is down while it's off, so the router (GL-BE9300, always on and
  # in the tailnet) sends it on its LAN bridge. Router setup is in the README.
  home-manager.users.john.programs.fish.functions.wake-desktop = {
    description = "Wake the desktop through the router and wait for it on the tailnet";
    body = ''
      ssh ROUTER-LOGIN-MOVED-TO-AGENIX etherwake -i br-lan DESKTOP-MAC-MOVED-TO-AGENIX
      or return
      echo "Magic packet sent, waiting for the desktop..."
      for i in (seq 60)
          if tailscale ping --c 1 --timeout 2s desktop >/dev/null 2>&1
              echo "Desktop is up: ssh john@desktop"
              return 0
          end
          sleep 1
      end
      echo "Desktop did not come up within 3 minutes" >&2
      return 1
    '';
  };

  # Release this machine was first installed with. Leave it alone on upgrades
  # (see the README); it is not the NixOS version you are running.
  system.stateVersion = "26.05";
}
