# Desktop. Everything shared lives in modules/; only machine-specific bits go here.
# Graphics run on Mesa (modules/nixos/desktop.nix), which covers AMD and Intel
# without vendor drivers. See the README if this machine ever needs NVIDIA's.
{ pkgs, ... }:
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

  # Elgato Stream Deck. Elgato's app is Windows/macOS only; StreamController is
  # the Linux replacement. The module also installs its udev rules, which give
  # the logged-in user access to the deck's USB device.
  programs.streamcontroller.enable = true;

  # Focusrite Scarlett Solo (3rd gen, 1235:8211). Class-compliant USB audio, so
  # PipeWire (modules/nixos/audio.nix) plays and records through it as is, and
  # the kernel's Scarlett driver exposes its switches as ALSA controls.
  # alsa-scarlett-gui is the Linux stand-in for Focusrite Control: 48V phantom
  # power, Air, Inst, and turning off MSD mode, which otherwise shows a "Scarlett
  # Welcome Disk" USB drive and hides some controls. The laptop never has it.
  home-manager.users.john.home.packages = [ pkgs.alsa-scarlett-gui ];

  # Wooting 60HE (vendor 31e3). Installs Wootility and the udev rules that give
  # the logged-in user access to the keyboard, which Wootility needs to read and
  # write its profiles (actuation, rapid trigger; stored on the keyboard).
  # Kanata (modules/nixos/kanata.nix) already grabs it like any other keyboard.
  # Wootility comes from unstable, wrapped for XWayland (overlays/default.nix).
  hardware.wooting.enable = true;

  # Which side of this machine the laptop sits on, and whose certificate to trust.
  home-manager.users.john.xdg.configFile."lan-mouse/config.toml".source = ./lan-mouse.toml;

  # Release this machine was first installed with. Leave it alone on upgrades
  # (see the README); it is not the NixOS version you are running.
  system.stateVersion = "26.05";
}
