# Desktop. Everything shared lives in modules/; only machine-specific bits go here.
# Graphics run on Mesa (modules/nixos/desktop.nix), which covers AMD and Intel
# without vendor drivers. See the README if this machine ever needs NVIDIA's.
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Niri's config.kdl ends with `include optional=true "host.kdl"`; this fills it
  # with the desktop's monitor layout.
  home-manager.users.jpierre.xdg.configFile."niri/host.kdl".source = ./niri-outputs.kdl;

  # Release this machine was first installed with. Leave it alone on upgrades
  # (see the README); it is not the NixOS version you are running.
  system.stateVersion = "26.05";
}
