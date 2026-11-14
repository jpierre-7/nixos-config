# backlog: Mod+B (config/niri/config.kdl) files a one-line idea as an issue in a
# project's tracker, queued offline. The project list is secrets/backlog-projects.age,
# decrypted by backlog itself with ~/.ssh/id_ed25519 on each run, so editing it
# (agenix -e) needs no rebuild. Script: pkgs/backlog/.
{
  lib,
  pkgs,
  repoDir,
  ...
}:
let
  backlog = pkgs.callPackage ../../pkgs/backlog {
    secretFile = "${repoDir}/secrets/backlog-projects.age";
  };
in
{
  home.packages = [ backlog ];

  systemd.user.services.backlog-flush = {
    Unit = {
      Description = "File the ideas backlog queued while offline";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe backlog} flush --notify";
      # A filed notification waits for its Open action; the oneshot exits without it, so leave it running.
      KillMode = "process";
    };
  };

  systemd.user.timers.backlog-flush = {
    Unit.Description = "Retry the backlog queue every 15 minutes";
    Timer = {
      OnStartupSec = "2min";
      OnUnitActiveSec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
