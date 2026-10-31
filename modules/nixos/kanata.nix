{
  # Home-row mods and Caps Lock -> Escape for every keyboard, below the
  # compositor, so they also work on the greeter and TTYs. Replaces keyd: kanata's
  # opposite-hand tap-hold keeps fast rolls as letters. The keymap is
  # config/kanata/keymap.kbd; it needs kanata from unstable (overlays/default.nix).
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
}
