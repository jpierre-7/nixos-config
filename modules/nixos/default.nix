# System configuration shared by every host.
{
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./boot.nix
    ./desktop.nix
    ./fonts.nix
    ./keyd.nix
    ./locale.nix
    ./networking.nix
    ./nix-ld.nix
    ./nix.nix
    ./printing.nix
    ./users.nix
  ];
}
