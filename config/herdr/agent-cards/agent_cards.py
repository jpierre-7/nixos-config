"""Agent cards: a pixel-art column of herdr's spaces and their agents.

Herdr plugins can't draw on its sidebar, only in panes, so this docks one pane
at the left of every tab and hides the real sidebar (config/herdr/config.toml).
Packaged and linked in modules/home/herdr.nix.

  herdr-agent-cards panel    what runs in the docked pane
  herdr-agent-cards dock     dock into the tabs named by a hook, or all of them
  herdr-agent-cards toggle   dock into the focused tab, or close its panel
  herdr-agent-cards navigate move the keyboard into the focused tab's panel
"""

import colorsys
import fcntl
import json
import os
import re
import selectors
import signal
import socket
import sys
import tempfile
import termios
import time
import tomllib
import tty
import unicodedata
import zlib

PLUGIN_ID = "local.agent-cards"
LABEL = "agents"
# Includes the two columns of the frame herdr draws around a pane.
WIDTH = 36
SOCKET = os.environ.get("HERDR_SOCKET_PATH", "")
# Noctalia writes this on every wallpaper change, and WezTerm's colors come from
# it too (modules/home/noctalia.nix), so the cards stay in step with the panes.
PALETTE = os.path.expanduser("~/.config/wezterm/colors/Noctalia.toml")
EVENTS = [
    "workspace.created", "workspace.updated", "workspace.renamed",
    "workspace.moved", "workspace.reordered", "workspace.closed",
    "workspace.focused", "tab.created", "tab.closed", "tab.focused",
    "tab.renamed", "tab.moved", "pane.created", "pane.closed", "pane.updated",
    "pane.focused", "pane.moved", "pane.exited", "pane.agent_detected",
]
# Claude animates its terminal title, so pane.updated can fire many times a
# second, once for every panel in the session.
REFRESH_GAP = 0.25
IDLE_TICK = 2.0
FRAME_TICK = 0.4

# 8x8, two pixels per terminal cell. a: accent, d: dark, l: light, k: eye, w: white.
SPRITES = [
    ("...aa...", ".aaaaaa.", ".awaawa.", ".akaaka.", ".aaaaaa.", "..dddd..", ".aa..aa.", ".d....d."),
    ("a......a", "aa....aa", "aaaaaaaa", "akaaaaka", "aaaddaaa", ".aaaaaa.", ".a.aa.a.", ".d.dd.d."),
    ("..aaaa..", ".aaaaaa.", "awwaawwa", "akwaakwa", "aaaaaaaa", "aaaaaaaa", "aaddaada", "a.aa.aa."),
    ("........", "...aa...", "..alaa..", ".allaaa.", ".akaaka.", "aaaaaaaa", "aaaddaaa", ".dddddd."),
    ("..aaaa..", ".awaaaa.", "aaaawwaa", "aaaaaaaa", ".dddddd.", "..wkwk..", "..wwww..", "..wwww.."),
    ("a......a", ".aaaaaa.", "awwaawwa", "awkaakwa", ".aaddaa.", ".alllla.", ".alllla.", "..d..d.."),
    ("...aa...", "..awwa..", "..akka..", "..aaaa..", ".daaaad.", "d.aaaa.d", "..dddd..", "...ll..."),
    ("a......a", "a.a..a.a", ".aaaaaa.", ".akaaka.", "aaaaaaaa", "a.aaaa.a", "..a..a..", ".a....a."),
]
SPINNER = "◐◓◑◒"


class ApiError(Exception):
    pass


def request(sock, method, params):
    message = {"id": "agent-cards", "method": method, "params": params}
    sock.sendall(json.dumps(message).encode() + b"\n")
    buffer = b""
    while b"\n" not in buffer:
        chunk = sock.recv(65536)
        if not chunk:
            raise ApiError(f"{method}: connection closed")
        buffer += chunk
    line, _, rest = buffer.partition(b"\n")
    reply = json.loads(line)
    if "error" in reply:
        raise ApiError(f"{method}: {reply['error']}")
    return reply["result"], rest


def call(method, params=None):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.connect(SOCKET)
        return request(sock, method, params or {})[0]


def snapshot():
    return call("session.snapshot")["snapshot"]


# Colors


def parse_hex(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, amount):
    return tuple(round(x + (y - x) * amount) for x, y in zip(a, b))


def load_palette():
    # Greys until Noctalia has written its first palette.
    colors = {
        "background": "#16181c", "foreground": "#d8dade",
        "ansi": ["#16181c", "#d9646f", "#8fbf7f", "#d6b26a", "#7fa8d6", "#b48fd6", "#7fc4c4", "#d8dade"],
    }
    try:
        with open(PALETTE, "rb") as file:
            colors = tomllib.load(file)["colors"]
    except (OSError, KeyError, tomllib.TOMLDecodeError):
        pass
    accents = []
    for value in colors["ansi"][2:7]:
        rgb = parse_hex(value)
        if rgb not in accents:
            accents.append(rgb)
    return {
        "bg": parse_hex(colors["background"]),
        "fg": parse_hex(colors["foreground"]),
        "red": parse_hex(colors["ansi"][1]),
        "green": parse_hex(colors["ansi"][2]),
        "accents": spread(accents),
    }


def spread(accents):
    # A wallpaper's palette can land on one hue, which would make every space
    # the same color. Fan out the brightest accent's hue, keeping its saturation
    # and lightness, so the set still belongs to the wallpaper.
    def hls(rgb):
        return colorsys.rgb_to_hls(*(c / 255 for c in rgb))

    hues = [hls(rgb)[0] for rgb in accents]
    if max(hues) - min(hues) > 0.25 and len(accents) >= 4:
        return accents
    hue, light, saturation = hls(max(accents, key=lambda rgb: hls(rgb)[2] * hls(rgb)[1]))
    offsets = (0, 0.05, -0.05, 0.1, -0.1, 0.15)
    return [
        tuple(round(c * 255) for c in colorsys.hls_to_rgb((hue + o) % 1, light, saturation))
        for o in offsets
    ]


def assign(labels, size):
    # Stable per space, moving on only when a neighbor already took the slot.
    taken = {}
    used = set()
    for label in labels:
        slot = zlib.crc32(label.encode()) % size
        for _ in range(size):
            if slot not in used:
                break
            slot = (slot + 1) % size
        used.add(slot)
        if len(used) == size:
            used = set()
        taken[label] = slot
    return taken


# Drawing


def width_of(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def fit(text, width):
    if width <= 0:
        return ""
    if width_of(text) > width:
        while text and width_of(text) > width - 1:
            text = text[:-1]
        text += "…"
    return text + " " * (width - width_of(text))


def seg(text, fg=None, bg=None, bold=False):
    codes = []
    if bold:
        codes.append("1")
    if fg:
        codes.append("38;2;%d;%d;%d" % fg)
    if bg:
        codes.append("48;2;%d;%d;%d" % bg)
    return f"\x1b[{';'.join(codes)}m{text}\x1b[0m"


def sprite_rows(index, accent, tile, frame):
    colors = {
        "a": accent,
        "d": mix(accent, (0, 0, 0), 0.45),
        "l": mix(accent, (255, 255, 255), 0.55),
        "k": (16, 18, 20),
        "w": (240, 242, 240),
    }
    # A working agent bobs up and down by one pixel.
    pixels = list(SPRITES[index % len(SPRITES)])
    if frame:
        pixels = pixels[1:] + ["........"]
    rows = []
    for y in range(0, 8, 2):
        cells = []
        for top, bottom in zip(pixels[y], pixels[y + 1]):
            cells.append(seg("▀", colors.get(top, tile), colors.get(bottom, tile)))
        rows.append("".join(cells))
    return rows


def wrap_title(text, width):
    if width_of(text) <= width:
        return text, ""
    head = text[:width]
    cut = head.rfind(" ")
    if cut > width // 2:
        return text[:cut], text[cut + 1:]
    return head, text[width:].lstrip()


def badge(state, frame, accent, palette, tint):
    if state == "working":
        return seg(f" {SPINNER[frame % 4]} WORKING ", palette["bg"], accent, True)
    if state == "blocked":
        return seg(" ! NEEDS YOU ", palette["bg"], palette["red"], True)
    if state == "done":
        return seg(" ✓ DONE ", palette["bg"], palette["green"], True)
    if state == "shell":
        return seg(" SHELL ", mix(palette["fg"], tint, 0.35), mix(tint, palette["fg"], 0.12))
    if state == "unknown":
        return seg(" ? ", mix(palette["fg"], tint, 0.35), mix(tint, palette["fg"], 0.12))
    return seg(" z IDLE ", mix(accent, tint, 0.2), mix(tint, accent, 0.18))


def card_lines(card, width, accent, palette, frame, sprite):
    tint = mix(palette["bg"], accent, 0.10)
    tile = mix(palette["bg"], accent, 0.22)
    lit = card["focused"] or card["selected"]
    edge = accent if lit else mix(palette["bg"], accent, 0.45)
    corners = "┏━┓┃┗┛" if lit else "┌─┐│└┘"
    text_width = width - 13
    bob = frame % 2 if card["state"] == "working" else 0
    art = sprite_rows(sprite, accent, tile, bob)
    head, tail = wrap_title(card["title"], text_width)
    pad_badge = text_width - width_of(re.sub(r"\x1b\[[0-9;]*m", "", badge(card["state"], frame, accent, palette, tint)))
    rows = [
        badge(card["state"], frame, accent, palette, tint) + seg(" " * pad_badge, bg=tint),
        seg(fit(head, text_width), palette["fg"], tint, True),
        seg(fit(tail, text_width), mix(palette["fg"], tint, 0.3), tint),
        seg(fit("└ " + card["footer"], text_width), mix(accent, tint, 0.3), tint),
    ]
    lines = [seg(corners[0] + corners[1] * (width - 2) + corners[2], edge, tint)]
    side = seg(corners[3], edge, tint)
    gap = seg(" ", bg=tint)
    for picture, text in zip(art, rows):
        lines.append(side + gap + picture + gap + text + gap + side)
    lines.append(seg(corners[4] + corners[1] * (width - 2) + corners[5], edge, tint))
    return lines


def section_header(name, busy, total, width, accent, palette):
    count = f" {busy}/{total}"
    room = width - len(count) - 2
    title = name.upper()
    if width_of(title) > room - 1:
        title = fit(title, room - 1).rstrip()
    rule = "─" * (room - width_of(title))
    return "".join([
        seg("▌", accent),
        seg(title + " ", accent, None, True),
        seg(rule[1:], mix(palette["bg"], accent, 0.35)),
        seg(count, mix(accent, palette["bg"], 0.25)),
    ])


# Model


def tab_name(tab):
    # Herdr numbers unnamed tabs, and a bare number needs the word to mean much.
    label = tab.get("label", "?")
    return f"tab {label}" if label.isdigit() else label


def build_sections(snap, selected):
    panes = [p for p in snap["panes"] if p.get("label") != LABEL]
    tabs = {t["tab_id"]: t for t in snap["tabs"]}
    sections = []
    for workspace in snap["workspaces"]:
        members = [p for p in panes if p["workspace_id"] == workspace["workspace_id"]]
        agents = [p for p in members if p.get("agent")]
        if not agents:
            active = workspace.get("active_tab_id")
            agents = [p for p in members if p["tab_id"] == active][:1]
        cards = []
        for pane in agents:
            agent = pane.get("agent")
            tab = tabs.get(pane["tab_id"], {})
            cwd = pane.get("foreground_cwd") or pane.get("cwd") or ""
            folder = os.path.basename(cwd) or "shell"
            title = (pane.get("title") or pane.get("terminal_title_stripped") or folder) if agent else folder
            cards.append({
                "pane_id": pane["pane_id"],
                "workspace_id": workspace["workspace_id"],
                "state": pane.get("agent_status", "unknown") if agent else "shell",
                "title": title,
                "footer": f"{agent or 'shell'} · {tab_name(tab)}",
                "focused": pane["pane_id"] == snap.get("focused_pane_id"),
                "selected": pane["pane_id"] == selected,
            })
        busy = sum(c["state"] in ("working", "blocked") for c in cards)
        sections.append({"workspace": workspace, "cards": cards, "busy": busy})
    return sections


def build_frame(snap, cols, frame, palette, selected):
    width = max(cols - 1, 20)
    labels = [w["label"] for w in snap["workspaces"]]
    hues = assign(labels, len(palette["accents"]))
    sprites = assign(labels, len(SPRITES))
    sections = build_sections(snap, selected)
    busy = sum(s["busy"] for s in sections)
    dim = mix(palette["fg"], palette["bg"], 0.45)
    right = f"{busy} BUSY"
    lines = [
        (seg("▓▒░ ", dim) + seg(fit("AGENTS", width - 4 - len(right)), dim, None, True) + seg(right, dim), None),
        ("", None),
    ]
    focus_line = 0
    for section in sections:
        label = section["workspace"]["label"]
        accent = palette["accents"][hues[label]]
        target = ("workspace", section["workspace"]["workspace_id"])
        header = section_header(label, section["busy"], len(section["cards"]), width, accent, palette)
        lines.append((header, target))
        for card in section["cards"]:
            if card["focused"] or card["selected"]:
                focus_line = len(lines)
            for line in card_lines(card, width, accent, palette, frame, sprites[label]):
                lines.append((line, ("pane", card["pane_id"])))
    animate = any(c["state"] == "working" for s in sections for c in s["cards"])
    order = [c["pane_id"] for s in sections for c in s["cards"]]
    return lines, focus_line, animate, order


# Panel


def terminal_size():
    # Not shutil's: it believes COLUMNS, and the restored shell a panel execs
    # from can leave a stale one behind.
    return os.get_terminal_size(sys.stdin.fileno())


class Panel:
    def __init__(self):
        self.pane_id = os.environ.get("HERDR_PANE_ID", "")
        self.snap = None
        self.frame = 0
        self.scroll = 0
        self.follow = None
        self.selected = None
        self.order = []
        self.lines = []
        self.drawn = {}
        self.animate = False
        self.naming = None
        self.back = None
        self.new_cwd = None
        self.palette = load_palette()
        self.palette_time = self.palette_mtime()
        self.size = terminal_size()

    @staticmethod
    def palette_mtime():
        try:
            return os.stat(PALETTE).st_mtime
        except OSError:
            return 0

    def visible(self):
        return bool(self.snap) and self.my_tab() == self.snap.get("focused_tab_id")

    def my_tab(self):
        for pane in self.snap["panes"]:
            if pane["pane_id"] == self.pane_id:
                return pane["tab_id"]
        return None

    def refresh(self):
        self.snap = snapshot()
        tab = self.my_tab()
        # Without this, closing a tab's last real pane would leave the tab open
        # with nothing in it but the panel.
        if tab and not [
            p for p in self.snap["panes"]
            if p["tab_id"] == tab and p["pane_id"] != self.pane_id and p.get("label") != LABEL
        ]:
            call("pane.close", {"pane_id": self.pane_id})
            raise SystemExit
        focused = self.snap.get("focused_pane_id")
        if focused == self.pane_id:
            self.selected = self.selected or self.back
        else:
            self.selected = None
            self.naming = None
            # Only this tab's panes: Esc shouldn't leave the tab.
            if self.visible():
                self.back = focused
        self.draw()

    def safe_refresh(self):
        # A hiccup talking to herdr shouldn't exit the panel, because that would
        # close its pane and collapse the tab's layout.
        try:
            self.refresh()
        except (ApiError, OSError):
            pass

    def draw(self):
        if not self.snap:
            return
        self.lines, focus_line, self.animate, self.order = build_frame(
            self.snap, self.size.columns, self.frame, self.palette, self.selected
        )
        rows = self.list_rows()
        most = max(len(self.lines) - rows, 0)
        if focus_line != self.follow:
            self.follow = focus_line
            if focus_line < self.scroll:
                self.scroll = max(focus_line - 1, 0)
            elif focus_line + 6 > self.scroll + rows:
                self.scroll = focus_line + 6 - rows
        self.scroll = min(self.scroll, most)
        out = ["\x1b[?2026h"]
        for row in range(rows):
            index = row + self.scroll
            text = self.lines[index][0] if index < len(self.lines) else ""
            if self.drawn.get(row) != text:
                self.drawn[row] = text
                out.append(f"\x1b[{row + 1};1H\x1b[0m\x1b[2K{text}")
        footer = self.footer()
        if self.drawn.get(rows) != footer:
            self.drawn[rows] = footer
            out.append(f"\x1b[{rows + 1};1H\x1b[0m\x1b[2K{footer}")
        out.append("\x1b[?2026l")
        sys.stdout.write("".join(out))
        sys.stdout.flush()

    def list_rows(self):
        return max(self.size.lines - 1, 1)

    def footer(self):
        # Hiding herdr's sidebar hides its "new" and "menu" too. A plugin can
        # create a space but can't open that menu, so the sidebar is the way there.
        width = max(self.size.columns - 1, 20)
        dim = mix(self.palette["fg"], self.palette["bg"], 0.45)
        if self.naming is not None:
            room = width - 8
            return seg(" name: ", dim) + seg(self.naming[-room:] + "▏", self.palette["fg"], None, True)
        hint = "^space b: menu"
        left = " + new"
        pad = " " * max(width - len(left) - len(hint), 1)
        return seg(left, self.palette["accents"][0], None, True) + seg(pad + hint, dim)

    def start_naming(self):
        focused = self.snap.get("focused_pane_id")
        panes = {p["pane_id"]: p for p in self.snap["panes"]}
        if focused != self.pane_id:
            self.back = focused
        # A new space should start where the pane being worked in is, as herdr's
        # new_cwd = "follow" would have it, not in the panel's folder.
        self.new_cwd = panes[self.back].get("foreground_cwd") if self.back in panes else None
        try:
            call("pane.focus", {"pane_id": self.pane_id})
        except ApiError:
            return
        self.snap["focused_pane_id"] = self.pane_id
        self.naming = ""
        self.draw()

    def on_naming(self, token):
        if token in (b"\r", b"\n"):
            params = {"focus": True}
            if self.naming.strip():
                params["label"] = self.naming.strip()
            if self.new_cwd:
                params["cwd"] = self.new_cwd
            self.naming = None
            try:
                call("workspace.create", params)
            except ApiError:
                pass
        elif token in (b"\x1b", b"\x03"):
            self.naming = None
            if self.back:
                self.jump(("pane", self.back))
        elif token in (b"\x7f", b"\x08"):
            self.naming = self.naming[:-1]
        elif not token.startswith(b"\x1b"):
            self.naming += "".join(c for c in token.decode(errors="ignore") if c.isprintable())
        self.draw()

    def fit_column(self):
        # Ratios stretch with the terminal, and the column should stay the width
        # the cards were drawn for. Only a full-height column is the root split.
        if not self.snap:
            return
        for layout in self.snap.get("layouts", []):
            mine = [p for p in layout["panes"] if p["pane_id"] == self.pane_id]
            area = layout["area"]
            if mine and is_column(mine[0]["rect"], area) and len(layout["panes"]) > 1:
                if abs(mine[0]["rect"]["width"] - WIDTH) > 1:
                    try:
                        call("layout.set_split_ratio", {
                            "tab_id": layout["tab_id"], "path": [],
                            "ratio": max(WIDTH / area["width"], 0.1),
                        })
                    except ApiError:
                        pass

    def jump(self, target):
        kind, value = target
        try:
            if kind == "workspace":
                call("workspace.focus", {"workspace_id": value})
            else:
                call("pane.focus", {"pane_id": value})
        except ApiError:
            pass

    def on_mouse(self, button, col, row, release):
        if button == 64:
            self.scroll = max(self.scroll - 3, 0)
            self.draw()
        elif button == 65:
            self.scroll = min(self.scroll + 3, max(len(self.lines) - self.list_rows(), 0))
            self.draw()
        elif button == 0 and not release and row > self.list_rows():
            if col <= 7 and self.naming is None:
                self.start_naming()
        elif button == 0 and not release:
            index = row - 1 + self.scroll
            if 0 <= index < len(self.lines) and self.lines[index][1]:
                self.jump(self.lines[index][1])

    def on_key(self, key):
        # Pane navigation can land here, so the column works from the keyboard too.
        if key in (b"\x1b", b"\x03") and self.back:
            self.jump(("pane", self.back))
        if not self.order:
            return
        if key in (b"j", b"\x1b[B", b"k", b"\x1b[A"):
            step = 1 if key in (b"j", b"\x1b[B") else -1
            current = self.selected or self.snap.get("focused_pane_id")
            index = self.order.index(current) if current in self.order else -step
            self.selected = self.order[(index + step) % len(self.order)]
            self.draw()
        elif key in (b"\r", b"\n") and self.selected:
            self.jump(("pane", self.selected))

    def on_input(self, data):
        tokens = rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])|\x1b\[[0-9;]*[A-Za-z~]|[\x1b\r\n\x7f\x03\x08]|[^\x1b\r\n\x7f\x03\x08]+"
        for match in re.finditer(tokens, data):
            token = match.group(0)
            if match.group(1):
                self.on_mouse(int(match.group(1)), int(match.group(2)), int(match.group(3)), match.group(4) == b"m")
            elif self.naming is not None:
                self.on_naming(token)
            elif token.startswith(b"\x1b"):
                self.on_key(token)
            else:
                for byte in token:
                    self.on_key(bytes([byte]))

    def run(self):
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin.fileno(), selectors.EVENT_READ, "input")
        events = socket.socket(socket.AF_UNIX)
        events.connect(SOCKET)
        _, rest = request(events, "events.subscribe", {"subscriptions": [{"type": t} for t in EVENTS]})
        selector.register(events, selectors.EVENT_READ, "events")
        wake_read, wake_write = os.pipe()
        os.set_blocking(wake_write, False)
        os.set_blocking(wake_read, False)
        signal.set_wakeup_fd(wake_write)
        signal.signal(signal.SIGWINCH, lambda *_: None)
        selector.register(wake_read, selectors.EVENT_READ, "resize")

        self.refresh()
        self.fit_column()
        due = None
        last_refresh = time.monotonic()
        last_frame = last_refresh
        while True:
            now = time.monotonic()
            animating = self.animate and self.visible()
            waits = [IDLE_TICK - (now - last_refresh)]
            if animating:
                waits.append(FRAME_TICK - (now - last_frame))
            if due is not None:
                waits.append(due - now)
            for key, _ in selector.select(max(min(waits), 0)):
                if key.data == "input":
                    data = os.read(key.fileobj, 4096)
                    if not data:
                        return
                    self.on_input(data)
                elif key.data == "events":
                    if not events.recv(65536):
                        return
                    due = due or now + REFRESH_GAP
                else:
                    os.read(wake_read, 4096)
                    self.size = terminal_size()
                    self.drawn = {}
                    self.safe_refresh()
                    self.fit_column()
            now = time.monotonic()
            if due is not None and now >= due:
                due = None
                last_refresh = now
                self.safe_refresh()
            elif now - last_refresh >= IDLE_TICK:
                last_refresh = now
                mtime = self.palette_mtime()
                if mtime != self.palette_time:
                    self.palette_time = mtime
                    self.palette = load_palette()
                    self.drawn = {}
                # A hidden panel doesn't need to poll: events still wake it.
                if self.visible():
                    self.safe_refresh()
            if animating and now - last_frame >= FRAME_TICK:
                last_frame = now
                self.frame += 1
                self.draw()


def run_panel():
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J")
    sys.stdout.flush()
    try:
        Panel().run()
    finally:
        sys.stdout.write("\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l")
        sys.stdout.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


# Docking


def find_panel(snap, tab_id):
    for pane in snap["panes"]:
        if pane["tab_id"] == tab_id and pane.get("label") == LABEL:
            return pane
    return None


def leftmost(snap, tab_id):
    for layout in snap.get("layouts", []):
        if layout["tab_id"] == tab_id and layout["panes"]:
            return min(layout["panes"], key=lambda p: (p["rect"]["x"], p["rect"]["y"]))["pane_id"]
    return None


def dock(tab_id):
    snap = snapshot()
    target = leftmost(snap, tab_id)
    if not target or find_panel(snap, tab_id):
        return
    panes = {p["pane_id"]: p for p in snap["panes"]}
    focused = snap.get("focused_pane_id")
    # The panel's cwd is what herdr's new_cwd = "follow" would inherit if it has
    # focus when a tab opens, so it shouldn't be the plugin's folder.
    opened = call("plugin.pane.open", {
        "plugin_id": PLUGIN_ID, "entrypoint": "cards", "placement": "split",
        "target_pane_id": target, "direction": "right", "focus": False,
        "cwd": panes[target].get("cwd"),
    })
    panel = find_pane_id(opened)
    call("pane.rename", {"pane_id": panel, "label": LABEL})
    # pane.split only goes right or down, so reach the left side with a swap.
    call("pane.swap", {"source_pane_id": panel, "target_pane_id": target})
    narrow(tab_id, panel)
    # Focus stays with the slot through a swap, not with the pane, and each tab
    # remembers its own. Left alone, switching to a tab docked in the background
    # would put the keyboard in the panel. Focusing there can switch tabs, so
    # go back to where the session was afterward.
    after = snapshot()
    layout = next(x for x in after["layouts"] if x["tab_id"] == tab_id)
    if layout.get("focused_pane_id") == panel:
        call("pane.focus", {"pane_id": target})
        if focused and focused != target:
            call("pane.focus", {"pane_id": focused})


def is_column(rect, area):
    return rect["x"] == 0 and rect["height"] == area["height"]


def narrow(tab_id, panel):
    layout = next(x for x in snapshot()["layouts"] if x["tab_id"] == tab_id)
    rect = next(p["rect"] for p in layout["panes"] if p["pane_id"] == panel)
    area = layout["area"]
    if is_column(rect, area):
        call("layout.set_split_ratio", {"tab_id": tab_id, "path": [], "ratio": max(WIDTH / area["width"], 0.1)})
        return
    # A tab that was already split: herdr can't insert a pane at the layout's
    # root, so the panel shares the top-left pane's slot. Resizing takes a delta
    # of the ratio of the split around the two panes.
    if rect["width"] > WIDTH:
        call("pane.resize", {"pane_id": panel, "direction": "left", "amount": (rect["width"] - WIDTH) / (rect["width"] * 2)})


def restore_panels(snap):
    # A session restore brings a panel's pane back as a plain shell in the same
    # slot. Run the panel in it, since a new one couldn't get full height back
    # in a tab that has been split since.
    for pane in snap["panes"]:
        if pane.get("label") != LABEL:
            continue
        info = call("pane.process_info", {"pane_id": pane["pane_id"]})
        if "panel" not in json.dumps(info):
            call("pane.send_input", {"pane_id": pane["pane_id"], "text": f" exec {sys.argv[0]} panel", "keys": ["enter"]})


def find_pane_id(value):
    if isinstance(value, dict):
        if "pane_id" in value:
            return value["pane_id"]
        for inner in value.values():
            found = find_pane_id(inner)
            if found:
                return found
    return None


def event_tabs():
    event = json.loads(os.environ.get("HERDR_PLUGIN_EVENT_JSON") or "null")
    found = set()

    def walk(value):
        if isinstance(value, dict):
            if "tab_id" in value:
                found.add(value["tab_id"])
            for inner in value.values():
                walk(inner)
        elif isinstance(value, list):
            for inner in value:
                walk(inner)

    walk(event)
    return found


def locked_dock(tabs):
    # A new workspace fires workspace.created and tab.created together, and both
    # hooks would otherwise see a tab with no panel yet.
    state = os.environ.get("HERDR_PLUGIN_STATE_DIR") or tempfile.gettempdir()
    with open(os.path.join(state, "dock.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for tab in tabs:
            dock(tab)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "panel"
    if command == "panel":
        run_panel()
    elif command == "dock":
        tabs = event_tabs()
        if not tabs:
            snap = snapshot()
            restore_panels(snap)
            tabs = [t["tab_id"] for t in snap["tabs"]]
        locked_dock(tabs)
    elif command == "toggle":
        snap = snapshot()
        tab = snap.get("focused_tab_id")
        panel = find_panel(snap, tab)
        if panel:
            call("pane.close", {"pane_id": panel["pane_id"]})
        else:
            locked_dock([tab])
    elif command == "navigate":
        snap = snapshot()
        tab = snap.get("focused_tab_id")
        if not find_panel(snap, tab):
            locked_dock([tab])
            snap = snapshot()
        call("pane.focus", {"pane_id": find_panel(snap, tab)["pane_id"]})
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
