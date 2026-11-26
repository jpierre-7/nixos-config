# Home Manager configuration shared by every host.
{
  imports = [
    ./airpods.nix
    ./apps.nix
    ./backlog.nix
    ./bind-palette.nix
    ./claude.nix
    ./dev.nix
    ./herdr.nix
    ./lan-mouse.nix
    ./neovim.nix
    ./niri.nix
    ./noctalia.nix
    ./qutebrowser.nix
    ./repeat.nix
    ./screensaver.nix
    ./shell.nix
    ./soundboard.nix
    ./syncthing.nix
    ./terminal.nix
    ./vicinae.nix
  ];
}
