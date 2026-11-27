# Call overlay: Mod+O makes the focused call window (Discord's call Pop Out,
# Teams' meeting window) a small floating window in the bottom-right corner,
# and the `follow` service moves it to every workspace that gets focus, on
# either monitor. The app's own window shows who's talking, the streams, and
# the hang-up button. Script: pkgs/call-overlay/; binds: config/niri/config.kdl.
{ pkgs, ... }:
let
  call-overlay = pkgs.callPackage ../../pkgs/call-overlay { };
in
{
  home.packages = [ call-overlay ];

  systemd.user.services.call-overlay = {
    Unit = {
      Description = "Move the call overlay to the focused workspace";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${call-overlay}/bin/call-overlay follow";
      # The event stream ends when niri restarts; come back with the new socket.
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
