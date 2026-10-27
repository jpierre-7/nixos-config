{
  # Caps Lock -> Escape for every keyboard, below the compositor, so it also
  # works on the greeter and TTYs.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main.capslock = "esc";
    };
  };
}
