# repeat: Mod+Shift+Period (config/niri/config.kdl) replays the last repeatable
# action, like vim's `.`. Each action records its own replay with
# `repeat record CMD ARG...` and carries repeat in its runtimeInputs; this puts
# the bare command on PATH for the bind. Script: pkgs/repeat/.
{ pkgs, ... }:
{
  home.packages = [ (pkgs.callPackage ../../pkgs/repeat { }) ];
}
