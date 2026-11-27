"""Unit tests for the game focus watcher's layer switching, without niri or kanata."""

import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("watcher", sys.argv.pop(1))
watcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watcher)

RULES = [
    ["osu!", "passthrough"],
    ["steam_app_0", "passthrough"],
    ["steam_app_.*", "game"],
    ["Minecraft.*", "game"],
]
HELD = ["fn1", "fn2"]


class FakeConnection(watcher.KanataConnection):
    def __init__(self, w):
        super().__init__(0, w)
        self.sock = object()
        self.track("hrm")
        self.sent = []
        self.held = None

    def send(self, message):
        self.sent.append(message)
        if "ChangeLayer" in message:
            self.layer_change(message["ChangeLayer"]["new"], self.held)

    def hold(self, layer):
        """Press (a layer) or release (None) a layer key, as kanata reports it."""
        self.layer_change(self.base, layer)

    def layer_change(self, base, held):
        # kanata reports a held layer over the base one, and only on a change.
        before = self.current
        self.held = held
        now = held or base
        if now != before:
            self.handle({"LayerChange": {"new": now}}, False)
        else:
            self.base = base


def windows(*app_ids, focused=0):
    return {
        "WindowsChanged": {
            "windows": [
                {"id": i, "app_id": a, "is_focused": i == focused}
                for i, a in enumerate(app_ids)
            ]
        }
    }


def focus(i):
    return {"WindowFocusChanged": {"id": i}}


class Test(unittest.TestCase):
    def setUp(self):
        self.w = watcher.Watcher(RULES, [], HELD)
        self.k = FakeConnection(self.w)
        self.w.instances = [self.k]
        self.w.update(windows("wezterm", "osu!", "steam_app_1245620", "Minecraft* 1.21", None))

    def test_mapping(self):
        layer = self.w.layer_for
        self.assertEqual(layer("osu!"), "passthrough")
        self.assertEqual(layer("steam_app_0"), "passthrough")
        self.assertEqual(layer("steam_app_1245620"), "game")
        self.assertEqual(layer("Minecraft* 1.21"), "game")
        self.assertIsNone(layer("wezterm"))
        self.assertIsNone(layer("xsteam_app_1"))
        self.assertIsNone(layer(None))

    def test_steam_game_gets_game_layer_and_restores(self):
        self.w.update(focus(2))
        self.assertEqual(self.k.current, "game")
        self.w.update(focus(0))
        self.assertEqual(self.k.current, "hrm")

    def test_osu_still_gets_passthrough(self):
        self.w.update(focus(1))
        self.assertEqual(self.k.current, "passthrough")
        self.w.update(focus(0))
        self.assertEqual(self.k.current, "hrm")

    def test_switch_between_games_restores_original(self):
        self.w.update(focus(1))
        self.w.update(focus(2))
        self.assertEqual(self.k.current, "game")
        self.w.update(focus(0))
        self.assertEqual(self.k.current, "hrm")

    def test_manual_layer_survives(self):
        for manual in ("passthrough", "base"):
            self.k.track(manual)
            self.w.update(focus(2))
            self.assertEqual(self.k.current, "game")
            self.w.update(focus(0))
            self.assertEqual(self.k.current, manual)

    def test_layer_held_as_game_takes_focus_is_not_restored(self):
        # Caps held for Fn1 as osu took focus left Fn1 on for good once it lost focus.
        self.k.hold("fn1")
        self.w.update(focus(1))
        self.k.hold(None)
        self.assertEqual(self.k.current, "passthrough")
        self.w.update(focus(0))
        self.assertEqual(self.k.current, "hrm")

    def test_layer_held_as_game_loses_focus_falls_back_to_base(self):
        self.w.update(focus(1))
        self.k.hold("fn1")
        self.w.update(focus(0))
        self.assertEqual(self.k.current, "fn1")
        self.k.hold(None)
        self.assertEqual(self.k.current, "hrm")

    def test_held_layer_on_connect_restores_start_layer(self):
        self.w.update(focus(1))
        k = FakeConnection(self.w)
        k.base = None
        k.handle({"LayerChange": {"new": "fn1"}}, True)
        self.assertEqual(k.sent, [{"RequestLayerNames": {}}])

    def test_null_app_id_is_not_a_game(self):
        self.w.update(focus(4))
        self.assertEqual(self.k.current, "hrm")
        self.assertEqual(self.k.sent, [])

    def test_stale_game_layer_on_connect_restores_start_layer(self):
        self.w.update(focus(1))
        k = FakeConnection(self.w)
        k.handle({"LayerChange": {"new": "game"}}, True)
        self.assertEqual(k.sent, [{"RequestLayerNames": {}}])
        k.handle({"LayerNames": {"names": ["hrm", "base", "game"]}}, False)
        self.assertEqual(k.current, "passthrough")
        self.assertEqual(k.saved, "hrm")

    def test_reload_reapplies_target(self):
        self.w.update(focus(2))
        self.k.handle({"ConfigFileReload": {}}, False)
        self.k.handle({"CurrentLayerName": {"name": "hrm"}}, False)
        self.assertEqual(self.k.current, "game")


if __name__ == "__main__":
    unittest.main()
