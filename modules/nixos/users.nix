{ pkgs, ... }:
{
  # Needed system-wide for fish to be a login shell (/etc/shells, completions).
  # The fish configuration itself lives in modules/home/shell.nix.
  programs.fish.enable = true;

  # No password in this public repo: set it with `passwd` after installing
  # (see the README), or switch to hashedPasswordFile with sops-nix/agenix.
  users.users.john = {
    isNormalUser = true;
    description = "John Pierre";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = pkgs.fish;
  };
}
