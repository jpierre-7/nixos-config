# System configuration shared by every host.
{
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./boot.nix
    ./desktop.nix
    ./fonts.nix
    ./kanata.nix
    ./locale.nix
    ./networking.nix
    ./nix-ld.nix
    ./nix.nix
    ./printing.nix
    ./users.nix
  ];
}
