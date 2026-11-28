{ config, lib, ... }:
{
  # Home-row mods and Caps Lock -> Escape for every keyboard, below the
  # compositor, so they also work on the greeter and TTYs. Replaces keyd: kanata's
  # opposite-hand tap-hold keeps fast rolls as letters. The keymap is
  # config/kanata/keymap.kbd; it needs kanata from unstable (overlays/default.nix).
  # The laptop splits this into two instances for tablet mode (hosts/laptop).
  services.kanata = {
    enable = true;
    keyboards.default = {
      # Empty: grab every device that looks like a keyboard.
      devices = [ ];
      # Pass keys missing from defsrc through kanata too, so the tap-hold
      # decisions see every keypress.
      extraDefCfg = "process-unmapped-keys yes";
      config = builtins.readFile ../../config/kanata/keymap.kbd;
      # TCP server for the game focus watcher (modules/home/game-focus-watcher.nix),
      # which switches layers through it. A bare port binds 127.0.0.1 only.
      port = 7070;
    };
  };

  # The watcher drives every instance, so each needs its own port.
  assertions =
    let
      ports = lib.mapAttrsToList (_: keyboard: keyboard.port) config.services.kanata.keyboards;
    in
    [
      {
        assertion = !lib.elem null ports && lib.allUnique ports;
        message = "Every services.kanata.keyboards instance needs its own port (game focus watcher).";
      }
    ];

  # The module leaves Restart=no. A keyboard that drops off USB and returns at
  # once (the desktop's Logitech receiver does) can vanish while kanata
  # re-registers it, and kanata exits with "failed read: No such device". The
  # home-row mods then stay off until a reboot. "always", not "on-failure":
  # the emergency exit (LCtrl+Space+Esc, easy to hit in a game) exits cleanly
  # and would leave kanata off too; a restart also clears any stuck key state.
  # To keep it off, `sudo systemctl stop kanata-<name>`. Every instance, so the
  # laptop's second one too. systemd's start limit (5 in 10 s) still stops a
  # crash loop.
  systemd.services = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "kanata-${name}" {
      serviceConfig = {
        Restart = "always";
        RestartSec = 2;
      };
    }
  ) config.services.kanata.keyboards;
}
