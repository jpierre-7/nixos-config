# Home Manager configuration shared by every host.
{
  imports = [
    ./airpods.nix
    ./apps.nix
    ./backlog.nix
    ./claude.nix
    ./dev.nix
    ./herdr.nix
    ./lan-mouse.nix
    ./neovim.nix
    ./niri.nix
    ./noctalia.nix
    ./qutebrowser.nix
    ./screensaver.nix
    ./shell.nix
    ./syncthing.nix
    ./terminal.nix
    ./vicinae.nix
  ];
}
