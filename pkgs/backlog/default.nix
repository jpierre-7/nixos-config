{
  age,
  coreutils,
  fuzzel,
  gawk,
  gh,
  gnugrep,
  jq,
  lib,
  libnotify,
  util-linux,
  wl-clipboard,
  writeShellApplication,
  yq-go,
  # The encrypted project list (secrets/backlog-projects.age), read in place from the checkout.
  secretFile,
}:
# vicinae, niri and qutebrowser come from PATH: the configured, running ones.
writeShellApplication {
  name = "backlog";
  runtimeInputs = [
    age
    coreutils
    fuzzel
    gawk
    gh
    gnugrep
    jq
    libnotify
    util-linux
    wl-clipboard
    yq-go
  ];
  text = ''
    backlog_secret=${lib.escapeShellArg secretFile}
  ''
  + builtins.readFile ./backlog.sh;
}
