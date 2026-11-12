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
    };
  };

  # The module leaves Restart=no. A keyboard that drops off USB and returns at
  # once (the desktop's Logitech receiver does) can vanish while kanata
  # re-registers it, and kanata exits with "failed read: No such device". The
  # home-row mods then stay off until a reboot. Every instance, so the laptop's
  # second one too. systemd's start limit (5 in 10 s) still stops a crash loop.
  systemd.services = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "kanata-${name}" {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 2;
      };
    }
  ) config.services.kanata.keyboards;
}
