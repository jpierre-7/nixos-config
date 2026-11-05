# Mouse and keyboard sharing across screen edges. Niri has no InputCapture portal
# or EIS, so Lan Mouse falls through to its layer-shell backend and emulates with
# wlr-virtual-pointer and virtual-keyboard. Each host links its own config.toml
# (hosts/*/lan-mouse.toml). The key in ~/.config/lan-mouse/lan-mouse.pem is
# generated on first start and stays out of the repo.
#
# Lan Mouse has no clipboard sharing, so lan-clip adds it. It trusts the machines
# and certificates in the Lan Mouse config and never sends a copy that offers
# x-kde-passwordManagerHint (overlays/noctalia-bitwarden-password-hint.patch).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  lan-clip = pkgs.callPackage ../../pkgs/lan-clip.nix { src = inputs.lan-clip; };
  configSource = "${config.xdg.configFile."lan-mouse/config.toml".source}";
in
{
  home.packages = [
    pkgs.lan-mouse
    lan-clip
  ];

  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "Lan Mouse";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      X-Restart-Triggers = [ configSource ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.lan-mouse} daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.lan-clip = {
    Unit = {
      Description = "lan-clip clipboard sync";
      # Lan Mouse generates the certificate lan-clip reads.
      After = [
        "graphical-session.target"
        "lan-mouse.service"
      ];
      PartOf = [ "graphical-session.target" ];
      # lan-clip reads the peer list only at startup, and a running daemon kept
      # accepting a peer after its fingerprint was removed. A restart fixes both.
      X-Restart-Triggers = [ configSource ];
    };
    Service = {
      ExecStart = "${lib.getExe lan-clip} daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
