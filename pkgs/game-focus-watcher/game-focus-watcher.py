"""Switch every kanata instance to a game's layer while that game has focus.

Each --layer PATTERN LAYER maps app-ids matching the regex PATTERN (whole
app-id) to LAYER; the first match wins. Reads niri's event stream for focus
changes and keeps a TCP connection to each kanata instance. On losing focus it
restores the layer the instance had before the game took it, so a manual
passthrough survives a session. Each --held-layer names a layer a key only
holds on (layer-while-held); it's never the one restored, since a held
layer restored with ChangeLayer stays on after the key is released. A layer
locked with layer-switch is indistinguishable from a held one, so a game
session ends it.
"""

import argparse
import json
import re
import socket
import subprocess
import threading
import time

lock = threading.Lock()


def log(*parts):
    print(*parts, flush=True)


class KanataConnection:
    """One kanata TCP server, reconnected for as long as the watcher runs.

    `saved` is the layer to restore once the game loses focus. It outlives a
    dropped connection, so a restore missed while disconnected still lands.
    `base` is the last layer seen that isn't held: what `current` falls back
    to once every layer key is released.
    """

    def __init__(self, port, watcher):
        self.port = port
        self.watcher = watcher
        self.sock = None
        self.current = None
        self.base = None
        self.saved = None

    def track(self, layer):
        self.current = layer
        if layer not in self.watcher.held:
            self.base = layer

    def send(self, message):
        try:
            self.sock.sendall((json.dumps(message) + "\n").encode())
        except OSError as err:
            log(f"kanata:{self.port}: send failed: {err}")

    def change_layer(self, layer):
        self.send({"ChangeLayer": {"new": layer}})

    def enter(self, layer):
        if self.sock is not None:
            # Kept across a move between games: the user's layer comes back.
            if self.saved is None:
                self.saved = self.base
            self.change_layer(layer)

    def leave(self):
        if self.sock is not None:
            self.restore()

    def restore(self):
        if self.saved is not None:
            self.change_layer(self.saved)
            self.saved = None

    def greeted(self, layer):
        # kanata greets each connection with its current layer.
        self.track(layer)
        target = self.watcher.target
        if target is None:
            self.restore()
        elif self.saved is None and self.base in self.watcher.layers | {None}:
            # A game layer left by an earlier watcher, or a held layer hiding
            # what's under it: restore the start layer.
            self.send({"RequestLayerNames": {}})
        else:
            if self.saved is None:
                self.saved = self.base
            self.change_layer(target)

    def handle(self, message, first):
        if "LayerChange" in message:
            if first:
                self.greeted(message["LayerChange"]["new"])
            else:
                self.track(message["LayerChange"]["new"])
        elif "LayerNames" in message:
            if self.saved is None:
                self.saved = message["LayerNames"]["names"][0]
            self.follow_target()
        elif "ConfigFileReload" in message:
            # A reload rebuilds the layout on its first layer, unannounced.
            self.send({"RequestCurrentLayerName": {}})
        elif "CurrentLayerName" in message:
            self.track(message["CurrentLayerName"]["name"])
            self.follow_target()

    def follow_target(self):
        target = self.watcher.target
        if target is not None and self.current != target:
            self.change_layer(target)

    def run(self):
        delay = 0.1
        while True:
            try:
                sock = socket.create_connection(("127.0.0.1", self.port))
            except OSError:
                time.sleep(delay)
                delay = min(delay * 2, 1.0)
                continue
            delay = 0.1
            log(f"kanata:{self.port}: connected")
            with lock:
                self.sock = sock
            first = True
            try:
                for line in sock.makefile("r", encoding="utf-8"):
                    with lock:
                        self.handle(json.loads(line), first)
                    first = False
            except (OSError, ValueError) as err:
                log(f"kanata:{self.port}: {err}")
            with lock:
                self.sock = None
                self.current = None
                self.base = None
            sock.close()
            log(f"kanata:{self.port}: disconnected")


class Watcher:
    """Tracks niri's focused window and drives every instance from it."""

    def __init__(self, rules, ports, held=()):
        self.rules = [(re.compile(pattern), layer) for pattern, layer in rules]
        self.layers = {layer for _, layer in rules}
        self.held = set(held)
        self.instances = [KanataConnection(port, self) for port in ports]
        self.windows = {}
        self.focused = None
        self.target = None

    def layer_for(self, app_id):
        if app_id is None:
            return None
        for pattern, layer in self.rules:
            if pattern.fullmatch(app_id):
                return layer
        return None

    def update(self, event):
        if "WindowsChanged" in event:
            windows = event["WindowsChanged"]["windows"]
            self.windows = {w["id"]: w["app_id"] for w in windows}
            self.focused = next(
                (w["id"] for w in windows if w["is_focused"]), None
            )
        elif "WindowOpenedOrChanged" in event:
            window = event["WindowOpenedOrChanged"]["window"]
            self.windows[window["id"]] = window["app_id"]
            if window["is_focused"]:
                self.focused = window["id"]
        elif "WindowClosed" in event:
            self.windows.pop(event["WindowClosed"]["id"], None)
        elif "WindowFocusChanged" in event:
            self.focused = event["WindowFocusChanged"]["id"]
        else:
            return
        target = self.layer_for(self.windows.get(self.focused))
        if target != self.target:
            self.target = target
            log(f"game focused: {target}" if target else "game unfocused")
            for instance in self.instances:
                if target:
                    instance.enter(target)
                else:
                    instance.leave()

    def connect(self):
        for instance in self.instances:
            threading.Thread(target=instance.run, daemon=True).start()

    def run(self, niri):
        connected = False
        while True:
            cmd = [niri, "msg", "--json", "event-stream"]
            with subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True) as p:
                for line in p.stdout:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    with lock:
                        self.update(event)
                    # niri opens the stream with WindowsChanged; until then a
                    # greeting's game layer can't be told stale from manual.
                    if not connected and "WindowsChanged" in event:
                        self.connect()
                        connected = True
            log("niri event stream ended; retrying")
            time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--niri", default="niri")
    parser.add_argument(
        "--layer",
        nargs=2,
        action="append",
        required=True,
        metavar=("PATTERN", "LAYER"),
    )
    parser.add_argument("--held-layer", action="append", default=[])
    parser.add_argument("--port", action="append", type=int, required=True)
    args = parser.parse_args()
    Watcher(args.layer, args.port, args.held_layer).run(args.niri)


if __name__ == "__main__":
    main()
