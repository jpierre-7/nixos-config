"""Agent cards: a sidebar of herdr's spaces and their agents, each a pixel bot.

Herdr plugins can't draw on its sidebar, only in panes, so this docks one pane
at the left of every tab and hides the real sidebar (config/herdr/config.toml).
Its look follows herdr's desktop app, as github.com/MarcozVD/herdr-layout-catppuccin
paints it, with colors from the wallpaper's palette. Packaged and linked in
modules/home/herdr.nix.

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
# About the 268 pixels the desktop app gives its sidebar.
WIDTH = 34
# At herdr's mobile_width_threshold, a full panel would leave the agent a few
# columns (Terminus on a phone is about 50), so it shrinks to a rail of status
# marks and opens as a drawer while it has focus.
NARROW = 64
RAIL = 5
# Below this the panel draws the rail, whatever the reason for its width.
MIN_COLUMNS = 20
SOCKET = os.environ.get("HERDR_SOCKET_PATH", "")
# Noctalia writes this on every wallpaper change, and WezTerm's colors come from
# it too (modules/home/noctalia.nix), so the panel stays in step with the panes.
PALETTE = os.path.expanduser("~/.config/wezterm/colors/Noctalia.toml")
COSTUME_FILE = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "herdr", "agent-cards-costumes.json",
)
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

# Rows a bot takes in the agents list. The design's rows are one line, but a
# costume needs more pixels than that to read.
AGENT_ROWS = 3
# A Claude bot, 8x6, two pixels per terminal cell. b: body, k: eye.
BOT = (
    "........",
    "........",
    ".bkbbkb.",
    "bbbbbbbb",
    ".bbbbbb.",
    ".b.bb.b.",
)
# Drawn over the bot by row, one per agent. h: apparel color, i: light trim,
# k: dark.
COSTUMES = (
    {0: "..hhhh..", 1: ".iiiiii."},  # top hat
    {0: "...ii...", 1: "..hhhh.."},  # party hat
    {0: ".i.ii.i.", 1: ".iiiiii."},  # crown
    {0: "...hh...", 1: ".hhihhh."},  # wizard
    {0: ".ii.ii..", 1: "...hh..."},  # propeller
    {0: "..hhhh..", 1: "hhhhhhhh"},  # cowboy
    {1: ".iiiiii.", 2: "h......h"},  # headphones
    {2: ".kikkik."},  # sunglasses
    {4: "..hiih.."},  # bow tie
    {3: ".hhhhhh.", 4: ".h......"},  # scarf
    {3: "h......h", 4: "hh....hh", 5: "hh....hh"},  # cape
    {1: ".hhihhh.", 2: ".kk....."},  # pirate
    {0: ".iiiiii.", 1: ".iiiiii."},  # chef
    {0: "...hh...", 1: ".iiiiii.", 2: ".i....i."},  # knight
    {0: ".i....i.", 1: ".i....i."},  # bunny ears
    {0: "...i....", 1: "...h....", 4: ".hhhhhh."},  # antenna and belt
)
# The agents list groups by state, most in need of you first.
GROUPS = (
    ("blocked", "Needs you"),
    ("working", "Working"),
    ("done", "Done"),
    ("idle", "Idle"),
    ("unknown", "Unknown"),
)
# Rounded ends for a row, like the design's pills. WezTerm draws these itself.
ROUND_LEFT = "\ue0b6"
ROUND_RIGHT = "\ue0b4"
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


def hls(rgb):
    return colorsys.rgb_to_hls(*(c / 255 for c in rgb))


def vividness(rgb):
    return hls(rgb)[2] * hls(rgb)[1]


def distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


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
    bg = parse_hex(colors["background"])
    fg = parse_hex(colors["foreground"])
    red = parse_hex(colors["ansi"][1])
    accents = spread(accents)
    body = max(accents, key=vividness)
    # Apparel has to stand out on the bot, and a wallpaper's accents can all
    # sit close to its body color.
    apparel = [c for c in accents + [red] if distance(c, body) > 70] or [red]
    return {
        "bg": bg,
        "fg": fg,
        "red": red,
        "green": parse_hex(colors["ansi"][2]),
        "accents": accents,
        "accent": body,
        "body": body,
        "apparel": apparel,
        # The design's surfaces, mixed from the wallpaper's instead of its
        # Catppuccin values: the column a shade off the panes, the lit row
        # stronger, text stepping down toward the background.
        "chrome": mix(bg, body, 0.07),
        "selected": mix(bg, body, 0.24),
        "muted": mix(fg, bg, 0.3),
        "dim": mix(fg, bg, 0.5),
        "rule": mix(bg, fg, 0.18),
    }


def spread(accents):
    # A wallpaper's palette can land on one hue, which would make every space
    # the same color. Fan out the brightest accent's hue, keeping its saturation
    # and lightness, so the set still belongs to the wallpaper.
    hues = [hls(rgb)[0] for rgb in accents]
    if max(hues) - min(hues) > 0.25 and len(accents) >= 4:
        return accents
    hue, light, saturation = hls(max(accents, key=vividness))
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


def bot_pixels(costume, state, tick):
    grid = [list(row) for row in BOT]
    # Each agent keeps its own time, so a column of them doesn't blink as one.
    tick += costume * 3
    step = tick % 2
    if state == "working":
        # Walks in place and swings its arms.
        grid[5] = list(".b..b..." if step else "...b..b.")
        arm = 7 if step else 0
        grid[3][arm] = "."
        grid[2][arm] = "b"
    elif state == "blocked":
        # Waves for attention, eyes flashing.
        grid[3][7] = "."
        grid[2 - step][7] = "b"
        if step:
            grid[2][2] = grid[2][5] = "r"
    elif state == "done":
        # Arms up, with a sparkle.
        grid[3][0] = grid[3][7] = "."
        grid[2][0] = grid[2][7] = "b"
        grid[step][0 if step else 7] = "i"
    elif tick % 12 == 0:
        grid[2][2] = grid[2][5] = "d"
    for y, row in COSTUMES[costume % len(COSTUMES)].items():
        for x, pixel in enumerate(row):
            if pixel != ".":
                grid[y][x] = pixel
    return grid


def bot_rows(costume, state, tick, palette, tile):
    apparel = palette["apparel"]
    colors = {
        "b": palette["body"],
        "d": mix(palette["body"], (0, 0, 0), 0.45),
        "k": (16, 18, 20),
        "h": apparel[costume % len(apparel)],
        "i": palette["fg"],
        "r": palette["red"],
    }
    grid = bot_pixels(costume, state, tick)
    rows = []
    for y in range(0, len(grid), 2):
        cells = []
        for top, bottom in zip(grid[y], grid[y + 1]):
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


def state_color(state, palette):
    return {
        "blocked": palette["red"],
        "working": palette["accent"],
        "done": palette["green"],
    }.get(state, palette["dim"])


def state_mark(state, tick):
    # A space or pane with no agent in it has no state to show.
    return {
        "blocked": "!",
        "working": SPINNER[tick % 4],
        "done": "✓",
        "idle": "○",
    }.get(state, " ")


def ago(seconds):
    if seconds is None:
        return ""
    if seconds < 3600:
        return f"{max(int(seconds // 60), 1)}m"
    return f"{int(seconds // 3600)}h"


def blank_line(width, palette):
    return seg(" " * width, bg=palette["chrome"])


def agent_lines(agent, width, palette, tick):
    chrome = palette["chrome"]
    tile = palette["selected"] if agent["lit"] else chrome
    text_width = width - 11
    art = bot_rows(agent["costume"], agent["state"], tick, palette, tile)
    head, tail = wrap_title(agent["title"], text_width)
    right = f"{agent['ago']} {state_mark(agent['state'], tick)}".strip()
    rows = [
        "".join([
            seg(fit(agent["where"], text_width - len(right)), palette["fg"], tile, True),
            seg(right, state_color(agent["state"], palette), tile),
        ]),
        seg(fit(head, text_width), palette["muted"], tile),
        seg(fit(tail or agent["folder"], text_width), palette["dim"], tile),
    ]
    edge = seg(" ", bg=chrome)
    gap = seg(" ", bg=tile)
    return [edge + picture + gap + text + edge for picture, text in zip(art, rows)]


def child_line(child, width, palette):
    # A pane sharing the agent's tab, on the tree guide the design hangs them from.
    chrome = palette["chrome"]
    tile = palette["selected"] if child["lit"] else chrome
    guide = "└ " if child["last"] else "├ "
    return "".join([
        seg("    ", bg=chrome),
        seg(guide, palette["rule"], chrome),
        seg(">_ ", palette["dim"], tile),
        seg(fit(child["name"], width - 10), palette["fg"] if child["lit"] else palette["muted"], tile),
        seg(" ", bg=chrome),
    ])


def space_line(space, width, palette, tick):
    chrome = palette["chrome"]
    tile = palette["selected"] if space["lit"] else chrome
    letter = space["label"][:1].upper() or "?"
    return "".join([
        seg(ROUND_LEFT, tile, chrome) if space["lit"] else seg(" ", bg=chrome),
        seg(ROUND_LEFT, space["tint"], tile),
        seg(letter, palette["bg"], space["tint"], True),
        seg(ROUND_RIGHT, space["tint"], tile),
        seg(" " + fit(space["label"], width - 8) + " ", palette["fg"] if space["lit"] else palette["muted"], tile),
        seg(state_mark(space["state"], tick), state_color(space["state"], palette), tile),
        seg(ROUND_RIGHT, tile, chrome) if space["lit"] else seg(" ", bg=chrome),
    ])


def section_title(name, width, palette, right=""):
    chrome = palette["chrome"]
    return seg(" " + fit(name, width - 2 - len(right)), palette["dim"], chrome) + seg(right + " ", palette["muted"], chrome)


def group_title(state, name, count, width, palette):
    chrome = palette["chrome"]
    text = f" {name} "
    return seg(text, state_color(state, palette), chrome, True) + seg(fit(str(count), width - len(text)), palette["dim"], chrome)


def rule_line(width, palette):
    return seg("─" * width, palette["rule"], palette["chrome"])


def rail_lines(snap, rows, width, palette, tick):
    # Marks in the agents list's order, so the most urgent is on top.
    chrome = palette["chrome"]
    states = [p.get("agent_status", "unknown") for p in agent_panes(snap)]
    states.sort(key=lambda state: [key for key, _ in GROUPS].index(state) if state in dict(GROUPS) else len(GROUPS))
    lines = [seg(fit(" ≡", width), palette["muted"], chrome)]
    lines += [seg(fit(" " + state_mark(state, tick), width), state_color(state, palette), chrome) for state in states]
    blank = blank_line(width, palette)
    return [(line, ("open", None)) for line in (lines + [blank] * rows)[:rows]]


def menu_line(label, width, palette):
    return seg(fit("  " + label, width), palette["fg"], palette["selected"])


# Model


def costume_map(pane_ids, cached):
    # Each tab's panel draws every agent and they have to agree, and an agent
    # keeps its costume while others come and go, so the choices live in a file.
    if all(pane in cached for pane in pane_ids):
        return cached
    os.makedirs(os.path.dirname(COSTUME_FILE), exist_ok=True)
    with open(COSTUME_FILE + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(COSTUME_FILE) as file:
                saved = json.load(file)
        except (OSError, ValueError):
            saved = {}
        # Agents that have gone give theirs back.
        taken = {pane: saved[pane] for pane in pane_ids if pane in saved}
        size = len(COSTUMES)
        for pane in pane_ids:
            if pane not in taken:
                free = [i for i in range(size) if i not in taken.values()] or list(range(size))
                start = zlib.crc32(pane.encode()) % size
                taken[pane] = min(free, key=lambda i: (i - start) % size)
        with open(COSTUME_FILE + ".new", "w") as file:
            json.dump(taken, file)
        os.replace(COSTUME_FILE + ".new", COSTUME_FILE)
    return taken


def agent_panes(snap):
    return [p for p in snap["panes"] if p.get("agent") and p.get("label") != LABEL]


def build_spaces(snap, width, tick, palette, selected, tints):
    lines = []
    focus = None
    focused = snap.get("focused_workspace_id")
    for index, workspace in enumerate(snap["workspaces"]):
        target = ("workspace", workspace["workspace_id"])
        chosen = target == selected
        if chosen or (workspace["workspace_id"] == focused and focus is None):
            focus = index
        space = {
            "label": workspace["label"],
            "tint": tints[workspace["workspace_id"]],
            "state": workspace.get("agent_status", "unknown"),
            "lit": chosen or workspace["workspace_id"] == focused,
        }
        lines.append((space_line(space, width, palette, tick), target))
    return lines, focus


def build_agents(snap, width, tick, palette, selected, costumes, since):
    names = {w["workspace_id"]: w for w in snap["workspaces"]}
    tabs = {t["tab_id"]: t for t in snap["tabs"]}
    focused = snap.get("focused_pane_id")
    agents = agent_panes(snap)
    others = {}
    for pane in snap["panes"]:
        if not pane.get("agent") and pane.get("label") != LABEL:
            others.setdefault(pane["tab_id"], []).append(pane)

    lines = []
    order = []
    focus = None
    now = time.monotonic()
    placed = set()
    for state, title in GROUPS:
        members = [p for p in agents if p.get("agent_status", "unknown") == state]
        if not members:
            continue
        if lines:
            lines.append((blank_line(width, palette), None))
        lines.append((group_title(state, title, len(members), width, palette), None))
        for index, pane in enumerate(members):
            if index:
                lines.append((blank_line(width, palette), None))
            target = ("pane", pane["pane_id"])
            chosen = target == selected
            lit = chosen or pane["pane_id"] == focused
            if chosen or (lit and focus is None):
                focus = len(lines)
            cwd = pane.get("foreground_cwd") or pane.get("cwd") or ""
            folder = os.path.basename(cwd) or "~"
            workspace = names.get(pane["workspace_id"], {})
            where = workspace.get("label", "?")
            if workspace.get("tab_count", 1) > 1:
                where += f" · {tabs.get(pane['tab_id'], {}).get('number', '?')}"
            changed = since.get(pane["pane_id"])
            agent = {
                "costume": costumes.get(pane["pane_id"], 0),
                "state": state,
                "title": pane.get("label") or pane.get("title") or pane.get("terminal_title_stripped") or folder,
                "folder": folder,
                "where": where,
                "ago": ago(None if changed is None else now - changed),
                "lit": lit,
            }
            lines += [(line, target) for line in agent_lines(agent, width, palette, tick)]
            order.append(target)
            # A tab's other panes hang from its first agent.
            if pane["tab_id"] in placed:
                continue
            placed.add(pane["tab_id"])
            children = others.get(pane["tab_id"], [])
            for place, child in enumerate(children):
                target = ("pane", child["pane_id"])
                chosen = target == selected
                lit = chosen or child["pane_id"] == focused
                if chosen or (lit and focus is None):
                    focus = len(lines)
                child_cwd = child.get("foreground_cwd") or child.get("cwd") or ""
                row = {
                    "name": child.get("label") or os.path.basename(child_cwd) or "shell",
                    "last": place == len(children) - 1,
                    "lit": lit,
                }
                lines.append((child_line(row, width, palette), target))
                order.append(target)
    if not lines:
        lines = [(seg(fit(" No agents running", width), palette["dim"], palette["chrome"]), None)]
    return lines, order, focus


def build_frame(snap, width, tick, palette, selected, costumes, since):
    labels = [w["label"] for w in snap["workspaces"]]
    hues = assign(labels, len(palette["accents"]))
    tints = {w["workspace_id"]: palette["accents"][hues[w["label"]]] for w in snap["workspaces"]}
    spaces, space_focus = build_spaces(snap, width, tick, palette, selected, tints)
    agents, panes, agent_focus = build_agents(snap, width, tick, palette, selected, costumes, since)
    return {
        "spaces": spaces,
        "agents": agents,
        "space_focus": space_focus,
        "agent_focus": agent_focus,
        "animate": bool(agent_panes(snap)),
        "order": [target for _, target in spaces] + panes,
    }


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
        self.space_scroll = 0
        self.space_follow = None
        self.spaces_at = (0, 0)
        self.selected = None
        self.order = []
        self.screen = []
        self.costumes = {}
        self.states = {}
        self.since = {}
        self.tracking = False
        self.drawn = {}
        self.animate = False
        self.naming = None
        self.prompt_for = None
        self.menu = None
        self.menu_row = 0
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
        if self.menu and focused != self.menu["focused"]:
            self.menu = None
        if focused == self.pane_id:
            if not self.selected and self.back:
                self.selected = ("pane", self.back)
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
            # Focus opens and closes the drawer, and a tab that was in the
            # background may have missed a change of screen.
            if self.visible():
                self.fit_column()
        except (ApiError, OSError):
            pass

    def track_states(self):
        # Herdr doesn't say when an agent's state changed, so a panel can only
        # time the changes it saw itself: agents it starts up with show no time.
        now = time.monotonic()
        agents = {p["pane_id"]: p.get("agent_status", "unknown") for p in agent_panes(self.snap)}
        for pane, state in agents.items():
            if self.states.get(pane) != state:
                self.since[pane] = now if self.tracking else None
        self.states = agents
        self.tracking = True

    def draw(self):
        if not self.snap:
            return
        self.costumes = costume_map([p["pane_id"] for p in agent_panes(self.snap)], self.costumes)
        self.track_states()
        built = build_frame(self.snap, self.width(), self.frame, self.palette, self.selected, self.costumes, self.since)
        self.animate = built["animate"]
        self.order = built["order"]
        if self.size.columns < MIN_COLUMNS:
            self.screen = rail_lines(self.snap, self.size.lines, self.size.columns, self.palette, self.frame)
        else:
            self.screen = self.compose(built, self.list_rows())
            self.overlay_menu()
        out = ["\x1b[?2026h"]
        for row, (text, _) in enumerate(self.screen):
            if self.drawn.get(row) != text:
                self.drawn[row] = text
                out.append(f"\x1b[{row + 1};1H\x1b[0m\x1b[2K{text}")
        out.append("\x1b[?2026l")
        sys.stdout.write("".join(out))
        sys.stdout.flush()

    def compose(self, built, rows):
        # The agents take what the spaces leave: a bot is three rows and a space
        # is one, so the design's even split would mostly show blanks.
        width = self.width()
        palette = self.palette
        blank = (blank_line(width, palette), None)
        rule = (rule_line(width, palette), None)
        top = [blank, (section_title("Spaces", width, palette, "+"), ("new", None))]
        spaces = built["spaces"]
        room = min(len(spaces), max(rows // 3, 1))
        self.space_scroll = min(self.space_scroll, len(spaces) - room)
        focus = built["space_focus"]
        if focus is not None and focus != self.space_follow:
            self.space_follow = focus
            if focus < self.space_scroll:
                self.space_scroll = focus
            elif focus >= self.space_scroll + room:
                self.space_scroll = focus - room + 1
        self.spaces_at = (len(top), len(top) + room)
        screen = top + spaces[self.space_scroll:self.space_scroll + room]
        screen += [blank, rule, blank, (section_title("Agents", width, palette), None)]

        agents = built["agents"]
        room = max(rows - len(screen), 0)
        focus = built["agent_focus"]
        if focus is not None and focus != self.follow:
            self.follow = focus
            if focus < self.scroll:
                self.scroll = focus
            elif focus + AGENT_ROWS > self.scroll + room:
                self.scroll = focus + AGENT_ROWS - room
        self.scroll = min(self.scroll, max(len(agents) - room, 0))
        screen += agents[self.scroll:self.scroll + room]
        return (screen + [blank] * rows)[:rows] + self.footer()

    def width(self):
        return max(self.size.columns, MIN_COLUMNS)

    def list_rows(self):
        return max(self.size.lines - 3, 1)

    def footer(self):
        # Hiding herdr's sidebar hides its "menu" too, and a plugin can't open
        # that menu, so the sidebar is the way there.
        width = self.width()
        palette = self.palette
        chrome = palette["chrome"]
        rule = (rule_line(width, palette), None)
        settings = (seg(fit(" ⚙ Settings", width), palette["muted"], chrome), ("settings", None))
        if self.naming is not None:
            label = f" {self.prompt_for[2]}: "
            room = width - len(label) - 1
            shown = fit(self.naming[-room:] + "▏", room + 1)
            return [rule, settings, (seg(label, palette["dim"], chrome) + seg(shown, palette["fg"], chrome, True), None)]
        hint = "^space b "
        return [rule, settings, (seg(fit(" ≡ Menu", width - len(hint)), palette["muted"], chrome) + seg(hint, palette["dim"], chrome), None)]

    def overlay_menu(self):
        if not self.menu:
            return
        items = self.menu["items"]
        start = min(self.menu["row"], max(len(self.screen) - len(items), 0))
        for index, (label, _) in enumerate(items):
            self.screen[start + index] = (menu_line(label, self.width(), self.palette), ("menu", index))

    def open_menu(self, target, row):
        kind, value = target
        if kind == "workspace":
            workspace = next(w for w in self.snap["workspaces"] if w["workspace_id"] == value)
            items = [
                ("Rename space", lambda: self.start_prompt(("workspace", value, "rename"), workspace["label"])),
                ("New tab", lambda: call("tab.create", {"workspace_id": value, "focus": True})),
                ("Close space", lambda: self.confirm("workspace.close", {"workspace_id": value}, workspace["label"])),
            ]
        elif kind == "pane":
            pane = next(p for p in self.snap["panes"] if p["pane_id"] == value)
            name = pane.get("label") or pane.get("terminal_title_stripped") or "pane"
            items = [
                ("Rename pane", lambda: self.start_prompt(("pane", value, "rename"), pane.get("label") or "")),
                ("Close pane", lambda: self.confirm("pane.close", {"pane_id": value}, name)),
            ]
        else:
            return
        self.menu = {"items": items, "row": row - 1, "focused": self.snap.get("focused_pane_id")}
        self.draw()

    def confirm(self, method, params, name):
        # Closing a space or pane ends what runs in it, so it takes a second click.
        self.menu = {
            "items": [(f"Close {name}?", lambda: call(method, params)), ("Cancel", lambda: None)],
            "row": self.menu_row,
            "focused": self.snap.get("focused_pane_id"),
        }

    def pick_menu(self, index):
        self.menu_row = self.menu["row"]
        action = self.menu["items"][index][1]
        self.menu = None
        try:
            action()
        except ApiError:
            pass
        self.draw()

    def start_prompt(self, prompt_for, text=""):
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
        self.prompt_for = prompt_for
        self.naming = text
        self.draw()

    def finish_prompt(self):
        kind, value, _ = self.prompt_for
        text = self.naming.strip()
        self.naming = None
        if kind == "new":
            params = {"focus": True}
            if text:
                params["label"] = text
            if self.new_cwd:
                params["cwd"] = self.new_cwd
            call("workspace.create", params)
            return
        if kind == "workspace" and text:
            call("workspace.rename", {"workspace_id": value, "label": text})
        elif kind == "pane":
            call("pane.rename", {"pane_id": value, "label": text or None})
        if self.back:
            self.jump(("pane", self.back))

    def on_naming(self, token):
        if token in (b"\r", b"\n"):
            try:
                self.finish_prompt()
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
                want = WIDTH
                if area["width"] <= NARROW:
                    want = WIDTH if self.snap.get("focused_pane_id") == self.pane_id else RAIL
                if abs(mine[0]["rect"]["width"] - want) > 1:
                    try:
                        call("layout.set_split_ratio", {
                            "tab_id": layout["tab_id"], "path": [],
                            "ratio": min(max(want / area["width"], 0.1), 0.85),
                        })
                    except ApiError:
                        pass

    def jump(self, target):
        kind, value = target
        try:
            if kind == "workspace":
                call("workspace.focus", {"workspace_id": value})
            elif kind == "pane":
                call("pane.focus", {"pane_id": value})
            elif kind == "open":
                call("pane.focus", {"pane_id": self.pane_id})
            elif kind == "new":
                self.start_prompt(("new", None, "name"))
            elif kind == "settings":
                call("plugin.pane.open", {"plugin_id": PLUGIN_ID, "entrypoint": "settings", "placement": "overlay", "focus": True})
        except ApiError:
            pass

    def target_at(self, row):
        return self.screen[row - 1][1] if 0 < row <= len(self.screen) else None

    def on_mouse(self, button, col, row, release):
        if button in (64, 65):
            step = -3 if button == 64 else 3
            if self.spaces_at[0] <= row - 1 < self.spaces_at[1]:
                self.space_scroll = max(self.space_scroll + step, 0)
            else:
                self.scroll = max(self.scroll + step, 0)
            self.draw()
            return
        if release:
            return
        target = self.target_at(row)
        if self.menu:
            if button == 0 and target and target[0] == "menu":
                self.pick_menu(target[1])
            else:
                self.menu = None
                self.draw()
        elif button == 2 and target:
            self.open_menu(target, row)
        elif button == 0 and target:
            # The whole row carries the header's target, but only its + is a button.
            if target[0] != "new" or col >= self.width() - 2:
                self.jump(target)

    def on_key(self, key):
        # Pane navigation can land here, so the column works from the keyboard too.
        if key in (b"\x1b", b"\x03") and self.back:
            self.menu = None
            self.jump(("pane", self.back))
        if not self.order:
            return
        if key in (b"j", b"\x1b[B", b"k", b"\x1b[A"):
            step = 1 if key in (b"j", b"\x1b[B") else -1
            current = self.selected or ("pane", self.snap.get("focused_pane_id"))
            index = self.order.index(current) if current in self.order else -step
            self.selected = self.order[(index + step) % len(self.order)]
            self.draw()
        elif key in (b"\r", b"\n") and self.selected:
            self.jump(self.selected)
        elif key == b"r" and self.selected:
            kind, value = self.selected
            if kind == "workspace":
                label = next(w["label"] for w in self.snap["workspaces"] if w["workspace_id"] == value)
                self.start_prompt(("workspace", value, "rename"), label)
            else:
                label = next((p.get("label") for p in self.snap["panes"] if p["pane_id"] == value), None)
                self.start_prompt(("pane", value, "rename"), label or "")

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

        # Otherwise herdr opens its own pane menu on a right-click, which would
        # offer to rename this panel rather than the row under the mouse.
        try:
            call("pane.input.set", {"pane_id": self.pane_id, "right_click": "pane"})
        except ApiError:
            pass
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
