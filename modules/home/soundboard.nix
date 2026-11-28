# Soundboard with no app: sound-add, sound-pick, sound-stop, sound-volume
# (pkgs/soundboard/), on Mod+G, Mod+Shift+G and Mod+Ctrl+G (config/niri/config.kdl).
# The "Soundboard mic" they play into is in modules/nixos/audio.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  library = "${config.home.homeDirectory}/sounds";
in
{
  home.packages = [
    (pkgs.callPackage ../../pkgs/soundboard {
      inherit library;
      sink = "soundboard-in";
    })
  ];

  # Seeds ~/sounds from config/sounds/ so a new machine starts with the same
  # sounds. Copied, not linked: sound-add writes and renames in the folder, and
  # sound-pick lists only regular files (find -type f), not symlinks.
  # shortcut: a seeded sound deleted or renamed by hand comes back on the next
  # rebuild; delete it from config/sounds/ too to drop it for good.
  home.activation.seedSounds = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p ${lib.escapeShellArg library}
    for f in ${../../config/sounds}/*; do
      [ -e ${lib.escapeShellArg library}/"''${f##*/}" ] ||
        run install -m644 "$f" ${lib.escapeShellArg library}/
    done
  '';
}
