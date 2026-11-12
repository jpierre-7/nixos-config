# Desktop. Everything shared lives in modules/; only machine-specific bits go here.
# Graphics run on Mesa (modules/nixos/desktop.nix), which covers AMD and Intel
# without vendor drivers. See the README if this machine ever needs NVIDIA's.
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Niri's config.kdl ends with `include optional=true "host.kdl"`; this fills it
  # with the desktop's monitor layout.
  home-manager.users.john.xdg.configFile."niri/host.kdl".source = ./niri-outputs.kdl;

  # Wake-on-LAN, so the laptop's `wake-desktop` can power this machine on.
  # NetworkManager owns the wired NICs and would reset their WoL setting, so
  # tell it to arm magic-packet wake (flag 0x40) on every ethernet connection,
  # the global form of `nmcli c modify <conn> 802-3-ethernet.wake-on-lan magic`.
  # The firmware must also allow waking from LAN/PCIe (see the README).
  networking.networkmanager.settings.connection."ethernet.wake-on-lan" = 64;

  # The SINOWEALTH keyboard (258A:0150) sends F11/F12 plainly and volume
  # down/up with Fn. Swap them in its own keymap, so F11/F12 change the volume
  # (niri's XF86Audio binds) and Fn+F11/F12 reach apps (fullscreen, devtools).
  # Below kanata, so it sees the swapped keys, and other keyboards are
  # untouched. Volume comes as consumer (c00e*) or keyboard-page (7008*)
  # usages depending on the firmware, so both are mapped. Takes effect when the
  # keyboard is plugged in again (or `sudo udevadm trigger -s input`).
  services.udev.extraHwdb = ''
    evdev:input:b0003v258Ap0150*
     KEYBOARD_KEY_70044=volumedown
     KEYBOARD_KEY_70045=volumeup
     KEYBOARD_KEY_c00ea=f11
     KEYBOARD_KEY_c00e9=f12
     KEYBOARD_KEY_70081=f11
     KEYBOARD_KEY_70080=f12
  '';

  # Which side of this machine the laptop sits on, and whose certificate to trust.
  home-manager.users.john.xdg.configFile."lan-mouse/config.toml".source = ./lan-mouse.toml;

  # Release this machine was first installed with. Leave it alone on upgrades
  # (see the README); it is not the NixOS version you are running.
  system.stateVersion = "26.05";
}
