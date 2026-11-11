# Mouse and keyboard sharing across screen edges. Niri has no InputCapture portal
# or EIS, so Lan Mouse falls through to its layer-shell backend and emulates with
# wlr-virtual-pointer and virtual-keyboard. Each host links its own config.toml
# (hosts/*/lan-mouse.toml). The key in ~/.config/lan-mouse/lan-mouse.pem is
# generated on first start and stays out of the repo. The login screen runs a
# receive-only copy from the same config (modules/nixos/greeter.nix).
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

  # Mod+M in config/niri/config.kdl. Lan Mouse can't enter a client on demand: the
  # layer-shell backend starts capturing only when the pointer enters its 1 px strip
  # at the shared edge (feschber/lan-mouse#260, #482), and niri has no action that
  # moves the pointer. So this pushes the pointer into that edge with a virtual
  # pointer. Niri clamps the big move to the output's edge, and Lan Mouse starts
  # capturing as if the mouse had crossed it. One event, so no leftover motion
  # reaches the other machine. The small move away first leaves the strip in case
  # the pointer still sits on it after coming back. On the other machine, the same
  # bind sends input back: its niri sees the keys from Lan Mouse's virtual keyboard.
  clients = (lib.importTOML config.xdg.configFile."lan-mouse/config.toml".source).clients or [ ];
  client =
    lib.throwIfNot (builtins.length clients == 1)
      "lan-mouse-switch expects exactly one [[clients]] entry in lan-mouse.toml"
      (builtins.head clients);
  # Direction of the shared edge: 1 or -1 on one axis, 0 on the other.
  dx =
    {
      left = -1;
      right = 1;
    }
    .${client.position} or 0;
  dy =
    {
      top = -1;
      bottom = 1;
    }
    .${client.position} or 0;
  move = n: "${toString (n * dx)} ${toString (n * dy)}";
  lan-mouse-switch = pkgs.writeShellApplication {
    name = "lan-mouse-switch";
    runtimeInputs = [ pkgs.wlrctl ];
    text = ''
      wlrctl pointer move ${move (-4)}
      wlrctl pointer move ${move 100000}
    '';
  };
in
{
  home.packages = [
    pkgs.lan-mouse
    lan-clip
    lan-mouse-switch
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
