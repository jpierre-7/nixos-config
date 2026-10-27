# PLACEHOLDER: replace this entire file with the one NixOS generates on the
# laptop itself (see "Fresh install" in the README):
#
#   nixos-generate-config --root /mnt          # during install, then copy
#   /mnt/etc/nixos/hardware-configuration.nix  # over this file
#
#   sudo nixos-generate-config --show-hardware-config \
#     > hosts/laptop/hardware-configuration.nix   # on an installed system
#
# Then `git add` it: flakes only see files git knows about.
#
# The stub below is not real hardware. It only lets `nix flake check` and test
# builds evaluate before the real file exists. The root device does not exist,
# and the pre-switch check makes nixos-install / nixos-rebuild refuse to install
# or activate this system until the file has been replaced.
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  fileSystems."/" = {
    device = "/dev/disk/by-label/REPLACE-WITH-GENERATED-CONFIG";
    fsType = "ext4";
  };

  system.preSwitchChecks.hardwareConfigurationPlaceholder = ''
    echo "hosts/laptop/hardware-configuration.nix is still the placeholder." >&2
    echo "Generate it with nixos-generate-config on this machine first (see README)." >&2
    exit 1
  '';
}
