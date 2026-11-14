# Writes the effective binds (defaults plus config.py's) to ~/.cache/qutebrowser/binds.json for
# bind-palette (pkgs/bind-palette/), which reads them from there: sending the running browser a
# :command over IPC raises its window (qutebrowser#5094), stealing focus each time the palette
# opens. Sourced at the end of config.py (modules/home/qutebrowser.nix), after the binds.
# Adapted from HefKer/dots.
import json
import os

from qutebrowser.keyinput import keyutils


def _norm(key):
    return str(keyutils.KeySequence.parse(key))


def _dump():
    commands = c.bindings.commands
    out = {}
    for mode, binds in c.bindings.default.items():
        merged = {_norm(k): v for k, v in binds.items()}
        for k, v in (commands.get(mode) or {}).items():
            if v:
                merged[_norm(k)] = v
            else:
                merged.pop(_norm(k), None)
        out[mode] = merged
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "qutebrowser")
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, "binds.json")
    with open(path + ".tmp", "w") as f:
        json.dump(out, f)
    os.replace(path + ".tmp", path)


_dump()

# c and config are globals qutebrowser gives a sourced file.
# ruff: noqa: F821
# pyright: reportUndefinedVariable=false
