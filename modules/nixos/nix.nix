{ inputs, ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Building noctalia from source on all 16 cores ran 16 cc1plus at ~1.5 GB
  # each, the desktop ran out of its 28 GB and the OOM killer took the
  # desktop apps. Cap parallel compiles at 2 x 6, and run builds at idle
  # priority so the desktop stays responsive.
  nix.settings.cores = 6;
  nix.settings.max-jobs = 2;
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # Weekly cleanup. Generations younger than a week stay, so recent
  # rollbacks keep working.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;

  # VS Code, Slack, Vivaldi, Chrome, AnyDesk and Claude Code are unfree.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ (import ../../overlays { inherit inputs; }) ];
}
