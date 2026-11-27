"""The keymap viewer's data: keymap-drawer's SVG and parsed layers, joined with each key's kbd action."""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "kanata-keymap"
DRAWER = os.environ["KEYMAP_DRAWER"]
LAYOUT = os.environ["KEYMAP_LAYOUT"]

# keymap-drawer's 60% places keys by name, in this order.
CANON = (
    "grv 1 2 3 4 5 6 7 8 9 0 - = bspc "
    "tab q w e r t y u i o p [ ] \\ "
    "caps a s d f g h j k l ; ' ret "
    "lsft z x c v b n m , . / rsft "
    "lctl lmet lalt spc ralt rmet menu rctl"
).split()
# Its 60% has grv where the Wooting has esc, and ralt rmet menu rctl where the Wooting has ralt rctl menu Fn.
RENAME = {"esc": "grv", "rctl": "rmet", "rmet": "rctl"}


def drawing_kbd(text):
    """keymap.kbd with the renames, for keymap-drawer's parser: an alias definition is followed by "(", layer keys by two spaces."""
    out = []
    for line in text.splitlines():
        line = re.sub(r"^(\s*)esc (\s*[^ (])", r"\1grv \2", line)
        line = re.sub(r"(^|  )rctl ", r"\1@swap@ ", line)
        line = re.sub(r"(^|  )rmet ", r"\1rctl ", line)
        out.append(line.replace("@swap@", "rmet"))
    return "\n".join(out) + "\n"


def _read(text):
    """keymap.kbd's forms as nested lists."""
    tokens = re.findall(r'\(|\)|"[^"]*"|[^\s()]+', re.sub(r";;.*", "", text))
    stack = [[]]
    for tok in tokens:
        if tok == "(":
            stack.append([])
        elif tok == ")":
            done = stack.pop()
            stack[-1].append(done)
        else:
            stack[-1].append(tok)
    return stack[0]


def _flat(x):
    return x if isinstance(x, str) else "(" + " ".join(_flat(y) for y in x) + ")"


def _kbd(text):
    src, layers, aliases = [], {}, {}
    for f in _read(text):
        if not isinstance(f, list) or not f:
            continue
        if f[0] == "defsrc":
            src = f[1:]
        elif f[0] == "defalias":
            aliases.update((k, _flat(v)) for k, v in zip(f[1::2], f[2::2]))
        elif f[0] == "deflayermap":
            body = f[2:]
            layers[f[1][0]] = {k: _flat(v) for k, v in zip(body[::2], body[1::2])}
    return src, layers, aliases


def join(kbd_text, parsed):
    """Each layer's keys, by position: keymap-drawer's legends plus the kbd action behind them.

    A key a layer leaves unmapped falls through to defsrc, so it's named by its defsrc key and
    marked inherited. A key whose action holds a layer, directly or through an alias, is marked
    held on that layer: keymap-drawer only sees a layer-while-held written in the layer itself.
    """
    src, kbd_layers, aliases = _kbd(kbd_text)
    pos_of = {name: CANON.index(RENAME.get(name, name)) for name in src}
    name_at = {p: n for n, p in pos_of.items()}

    def expand(raw):
        return aliases.get(raw[1:], "") if raw.startswith("@") else raw

    holds = {}
    for mapped in kbd_layers.values():
        for name, raw in mapped.items():
            for target in re.findall(r"\(layer-while-held (\S+?)\)", expand(raw)):
                holds.setdefault(target, set()).add(pos_of[name])

    layers = []
    for lname, legends in parsed["layers"].items():
        mapped = kbd_layers.get(lname, {})
        keys = []
        for pos, v in enumerate(legends):
            leg = v if isinstance(v, dict) else ({"t": v} if v else {})
            sname = name_at.get(pos, CANON[pos])
            raw = mapped.get(sname, "")
            held = leg.get("type") == "held" or pos in holds.get(lname, ())
            inherited = not raw and not held
            tap = sname if inherited else str(leg.get("t", ""))
            words = [tap, leg.get("s", ""), leg.get("h", ""), raw]
            if raw.startswith("@"):
                words += [raw[1:], expand(raw)]
            keys.append({
                "pos": pos, "src": sname, "raw": raw,
                "t": tap, "s": str(leg.get("s", "")), "h": str(leg.get("h", "")),
                "held": held, "inherited": inherited,
                "search": " ".join(str(w) for w in words if w).lower(),
            })
        layers.append({"name": lname, "keys": keys})
    return {"layers": layers}


def _write(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def render(keymap_dir):
    """Draw keymap.svg and write keymap.json into the cache, both atomically."""
    keymap_dir = Path(keymap_dir)
    kbd_text = (keymap_dir / "keymap.kbd").read_text()
    config = keymap_dir / "keymap-drawer.yaml"
    with tempfile.TemporaryDirectory() as tmp:
        kbd = Path(tmp) / "keymap.kbd"
        kbd.write_text(drawing_kbd(kbd_text))
        yml = Path(tmp) / "keymap.yaml"
        svg = Path(tmp) / "keymap.svg"
        subprocess.run([DRAWER, "-c", config, "parse", "-k", kbd, "-o", yml], check=True)
        subprocess.run([DRAWER, "-c", config, "draw", "-j", LAYOUT, yml, "-o", svg], check=True)
        data = join(kbd_text, yaml.safe_load(yml.read_text()))
        CACHE.mkdir(parents=True, exist_ok=True)
        _write(CACHE / "keymap.svg", svg.read_bytes())
        _write(CACHE / "keymap.json", json.dumps(data).encode())


if __name__ == "__main__":
    render(sys.argv[1])
