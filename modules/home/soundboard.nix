# Soundboard with no app: sound-add, sound-pick, sound-stop, sound-volume
# (pkgs/soundboard/), on Mod+G, Mod+Shift+G and Mod+Ctrl+G (config/niri/config.kdl).
# The "Soundboard mic" they play into is in modules/nixos/audio.nix.
{ config, pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ../../pkgs/soundboard {
      library = "${config.home.homeDirectory}/sounds";
      sink = "soundboard-in";
    })
  ];
}
