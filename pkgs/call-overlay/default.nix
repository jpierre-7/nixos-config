{ writers }:
# Plain stdlib Python: it talks JSON to niri's socket, which `niri msg` can't
# do for a move by window id to a workspace by id (the CLI takes only an index
# or a name).
writers.writePython3Bin "call-overlay" { flakeIgnore = [ "E501" ]; } (
  builtins.readFile ./call_overlay.py
)
