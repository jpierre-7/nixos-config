# SSDs in the dual-bay USB enclosure (its UAS quirk is in boot.nix). Each has
# one ext4 partition, found by label, so it mounts on whichever host the
# enclosure is plugged into, whatever sdX name it gets.
#
# The enclosure is usually unplugged, so:
# - nofail + a 5s device timeout: a host without it boots with no wait.
# - automount: mounts on first access of /mnt/<label>, not at boot.
# - idle timeout: unmounts after 10 idle minutes, so the drive is usually
#   unmounted by the time the enclosure is pulled.
# A new drive's root is owned by root; `sudo chown john:users /mnt/<label>`
# once, and the owner is stored on the drive (README, "External SSDs").
let
  external = label: {
    device = "/dev/disk/by-label/${label}";
    fsType = "ext4";
    options = [
      "nofail"
      "noatime"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.device-timeout=5s"
    ];
  };
in
{
  fileSystems = {
    "/mnt/samsung" = external "samsung"; # Samsung 850 PRO 256GB
    "/mnt/tforce" = external "tforce"; # T-FORCE 1TB
  };
}
