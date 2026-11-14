{
  coreutils,
  gawk,
  jq,
  lib,
  libnotify,
  util-linux,
  wl-clipboard,
  writeShellApplication,
  yq-go,
  # kanata's keymap: the same file the kanata service loads (modules/nixos/kanata.nix). A path,
  # interpolated below so it is copied into the store and kept as a dependency.
  kanataKeymap,
}:
# vicinae, nvim and wezterm come from PATH: the palette asks the configured ones for their binds.
writeShellApplication {
  name = "bind-palette";
  runtimeInputs = [
    coreutils
    gawk
    jq
    libnotify
    util-linux
    wl-clipboard
    yq-go
  ];
  text = ''
    kanata_keymap=${lib.escapeShellArg "${kanataKeymap}"}
  ''
  + builtins.readFile ./bind-palette.sh;
}
