# Mouse and keyboard sharing across screen edges. Niri has no InputCapture portal
# or EIS, so Lan Mouse falls through to its layer-shell backend and emulates with
# wlr-virtual-pointer and virtual-keyboard. Each host links its own config.toml
# (hosts/*/lan-mouse.toml). The key in ~/.config/lan-mouse/lan-mouse.pem is
# generated on first start and stays out of the repo. The login screen runs a
# receive-only copy from the same config (modules/nixos/greeter.nix).
#
# While a machine shows its lock screen or screensaver, the other turns its edge
# to it off, so the cursor can't wander over by accident and get stuck there:
# the lock screen covers the way back. Mod+M still crosses (lan-mouse-switch).
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
  # Lan Mouse numbers clients from 0 in config order, and there is only one.
  clientId = "0";

  # Lock sync, UDP on the tailnet only (modules/nixos/networking.nix). Each
  # machine sends "locked" or "unlocked" once a second; the other acts only on a
  # change, so Mod+M's re-enabled edge stays on until the next lock.
  lockPort = 4244;
  lan-mouse-lock-notify = pkgs.writeShellApplication {
    name = "lan-mouse-lock-notify";
    runtimeInputs = with pkgs; [
      jq
      niri
      noctalia
      socat
    ];
    text = ''
      while true; do
        state=unlocked
        # The screensaver's windows (modules/home/screensaver.nix) count too: the
        # next input there locks.
        if [[ $(noctalia msg status 2>/dev/null | jq -r .locked) == true ]] ||
          niri msg --json windows 2>/dev/null | jq -e 'any(.[]; .app_id == "org.nixos.screensaver")' >/dev/null; then
          state=locked
        fi
        echo "$state" | socat -u - UDP4-SENDTO:${client.hostname}:${toString lockPort} || true
        sleep 1
      done
    '';
  };
  lan-mouse-lock-sync = pkgs.writeShellApplication {
    name = "lan-mouse-lock-sync";
    runtimeInputs = with pkgs; [
      lan-mouse
      socat
    ];
    text = ''
      last=
      socat -u UDP4-RECV:${toString lockPort} - | while read -r state; do
        [[ $state == "$last" ]] && continue
        case $state in
          locked) lan-mouse cli deactivate ${clientId} || continue ;;
          unlocked) lan-mouse cli activate ${clientId} || continue ;;
          *) continue ;;
        esac
        last=$state
      done
    '';
  };
  lan-mouse-switch = pkgs.writeShellApplication {
    name = "lan-mouse-switch";
    runtimeInputs = with pkgs; [
      gnugrep
      jq
      lan-mouse
      niri
      wlrctl
    ];
    text = ''
      # The edge is off while the other machine is locked (lan-mouse-lock-sync
      # below). Turn it back on and wait for its strip, so this bind still crosses.
      if lan-mouse cli list | grep -q 'active: false'; then
        lan-mouse cli activate ${clientId}
        for _ in $(seq 20); do
          niri msg --json layers | jq -e 'any(.[]; .namespace == "LAN Mouse Sharing")' >/dev/null && break
          sleep 0.05
        done
      fi
      wlrctl pointer move ${move (-4)}
      wlrctl pointer move ${move 100000}
    '';
  };

  # Lan Mouse looks the client's name up once at start and never again. A
  # rebuild that restarts tailscaled restarts Lan Mouse too, and if MagicDNS
  # is still down it keeps an empty address list until the next restart. So
  # wait up to 30 s for the name, then start anyway.
  wait-for-client = pkgs.writeShellScript "lan-mouse-wait-for-client" ''
    # A failed lookup can block for seconds on DNS timeouts, so cap each one
    # and the whole wait.
    while [ "$SECONDS" -lt 30 ]; do
      ${lib.getExe' pkgs.coreutils "timeout"} 2 ${lib.getExe' pkgs.getent "getent"} hosts ${lib.escapeShellArg client.hostname} >/dev/null && exit 0
      sleep 1
    done
  '';
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
      ExecStartPre = wait-for-client;
      ExecStart = "${lib.getExe pkgs.lan-mouse} daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.lan-mouse-lock-notify = {
    Unit = {
      Description = "Send this machine's lock state to the other's Lan Mouse";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe lan-mouse-lock-notify;
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.lan-mouse-lock-sync = {
    Unit = {
      Description = "Turn the Lan Mouse edge off while the other machine is locked";
      # A restarted Lan Mouse turns the edge back on; restarting with it forgets
      # the last state, so the next message applies again.
      After = [ "lan-mouse.service" ];
      PartOf = [ "lan-mouse.service" ];
    };
    Service = {
      ExecStart = lib.getExe lan-mouse-lock-sync;
      Restart = "always";
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
