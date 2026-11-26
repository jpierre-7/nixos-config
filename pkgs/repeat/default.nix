{
  coreutils,
  libnotify,
  writeShellApplication,
}:
writeShellApplication {
  name = "repeat";
  runtimeInputs = [
    coreutils
    libnotify
  ];
  text = builtins.readFile ./repeat.sh;
}
