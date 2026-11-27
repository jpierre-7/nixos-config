{ writers }:
writers.writePython3Bin "game-focus-watcher" { } (builtins.readFile ./game-focus-watcher.py)
