# System configuration shared by every host.
{
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./boot.nix
    ./desktop.nix
    ./external-drives.nix
    ./fonts.nix
    ./greeter.nix
    ./kanata.nix
    ./locale.nix
    ./networking.nix
    ./nix-ld.nix
    ./nix.nix
    ./printing.nix
    ./secrets.nix
    ./users.nix
  ];
}
