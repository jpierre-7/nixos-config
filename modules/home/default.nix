# Home Manager configuration shared by every host.
{
  imports = [
    ./airpods.nix
    ./apps.nix
    ./claude.nix
    ./dev.nix
    ./neovim.nix
    ./niri.nix
    ./noctalia.nix
    ./shell.nix
    ./syncthing.nix
    ./terminal.nix
    ./vicinae.nix
  ];
}
