"""call-overlay: one call window, small in a corner, on whatever workspace
has focus. Niri has no sticky windows, so `follow` (a user service) moves it
there on every workspace change. Binds: config/niri/config.kdl. Module:
modules/home/call-overlay.nix.

  call-overlay pin      make the focused window the overlay; again to undo
  call-overlay hide     stop following and leave it; again to bring it back
  call-overlay focus    focus the overlay; again to go back
  call-overlay follow   the service
"""

import json
import os
import socket
import sys
import time

# 16:9, big enough to read a screen share on the desktop's monitors.
WIDTH, HEIGHT, MARGIN = 640, 360, 16
STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                     "call-overlay.json")


def connect():
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.environ["NIRI_SOCKET"])
    return s


def request(req):
    with connect() as s:
        s.sendall((json.dumps(req) + "\n").encode())
        reply = json.loads(s.makefile().readline())
    if "Err" in reply:
        raise RuntimeError(f"niri: {reply['Err']}")
    return reply["Ok"]


def action(name, **args):
    return request({"Action": {name: args}})


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(state):
    if state is None:
        try:
            os.remove(STATE)
        except FileNotFoundError:
            pass
        return
    with open(STATE, "w") as f:
        json.dump(state, f)


def windows():
    return {w["id"]: w for w in request("Windows")["Windows"]}


def overlay():
    """The saved overlay state, or None once its window is gone."""
    state = load()
    if state and state["id"] not in windows():
        save(None)
        return None
    return state


def place(win_id):
    """Bottom-right corner, MARGIN from both edges of the working area.

    Niri's IPC doesn't report the working area (the output minus bars), so
    push the window to the far edge, where niri clamps it to leave
    clamp(size / 4, 10, 75) px on screen (Data::recompute_logical_pos in
    niri's src/layout/floating.rs), then step back the rest of the way.

    shortcut: hardcodes niri's clamp; if a niri update changes it the
    overlay lands off by up to 75 px, so re-check it then.
    """
    w, h = windows()[win_id]["layout"]["tile_size"]
    action("MoveFloatingWindow", id=win_id,
           x={"SetProportion": 100.0}, y={"SetProportion": 100.0})
    action("MoveFloatingWindow", id=win_id,
           x={"AdjustFixed": -(w + MARGIN - on_screen(w))},
           y={"AdjustFixed": -(h + MARGIN - on_screen(h))})


def on_screen(size):
    return min(max(size / 4, 10), 75)


def bring_here(win_id):
    focused = next(w for w in request("Workspaces")["Workspaces"]
                   if w["is_focused"])
    if windows()[win_id]["workspace_id"] != focused["id"]:
        action("MoveWindowToWorkspace", window_id=win_id,
               reference={"Id": focused["id"]}, focus=False)
    place(win_id)


def pin():
    focused = request("FocusedWindow")["FocusedWindow"]
    state = overlay()
    if state:
        action("MoveWindowToTiling", id=state["id"])
        save(None)
        if focused and focused["id"] == state["id"]:
            return
    if not focused:
        return
    win_id = focused["id"]
    action("MoveWindowToFloating", id=win_id)
    action("SetWindowWidth", id=win_id, change={"SetFixed": WIDTH})
    action("SetWindowHeight", id=win_id, change={"SetFixed": HEIGHT})
    # The app resizes on its own time, and place() needs the new size. Apps
    # with a bigger minimum never reach it, hence the cap.
    for _ in range(20):
        if windows()[win_id]["layout"]["window_size"] == [WIDTH, HEIGHT]:
            break
        time.sleep(0.05)
    place(win_id)
    save({"id": win_id, "hidden": False})


def hide():
    state = overlay()
    if not state:
        return
    state["hidden"] = not state["hidden"]
    save(state)
    if not state["hidden"]:
        bring_here(state["id"])


def focus():
    state = overlay()
    if not state:
        return
    focused = request("FocusedWindow")["FocusedWindow"]
    if focused and focused["id"] == state["id"]:
        action("FocusWindowPrevious")
    else:
        if state["hidden"]:
            hide()
        action("FocusWindow", id=state["id"])


def follow():
    with connect() as s:
        s.sendall(b'"EventStream"\n')
        lines = s.makefile()
        lines.readline()  # the reply to the request itself
        for line in lines:
            event = json.loads(line)
            if not event.get("WorkspaceActivated", {}).get("focused"):
                continue
            state = overlay()
            if state and not state["hidden"]:
                try:
                    bring_here(state["id"])
                except (RuntimeError, KeyError, StopIteration) as e:
                    # The window closed mid-move; the next event starts clean.
                    print(f"call-overlay: {e}", file=sys.stderr)


def main():
    cmds = {"pin": pin, "hide": hide, "focus": focus, "follow": follow}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    cmds[sys.argv[1]]()


if __name__ == "__main__":
    main()
