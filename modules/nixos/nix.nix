{ inputs, ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Weekly cleanup. Generations younger than two weeks stay, so recent
  # rollbacks keep working.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  # VS Code, Slack, Vivaldi, AnyDesk and Claude Code are unfree.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ (import ../../overlays { inherit inputs; }) ];
}
