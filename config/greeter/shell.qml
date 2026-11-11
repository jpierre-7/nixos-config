// Login screen, a Quickshell greeter on greetd (modules/nixos/greeter.nix).
// The look is Omarchy's SDDM theme (default/sddm/omarchy/Main.qml in
// basecamp/omarchy): a wordmark over a lock and an outlined password box that
// shows one bullet per character, both turning red after a wrong password.
// As there, the user and the session are fixed, so there is nothing to pick.
// In place of Omarchy's wordmark: the screensaver's NixOS logo
// (config/screensaver/nixos-logo.txt) and a "Welcome back!" typed out in
// pixel letters that then ripple now and then. The hostname sits small under
// the password box, to tell the machines apart.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Wayland

ShellRoot {
    id: root

    // Set by the greeter script in modules/nixos/greeter.nix.
    readonly property string user: Quickshell.env("GREETER_USER")
    readonly property string session: Quickshell.env("GREETER_SESSION")
    readonly property string host: Quickshell.env("GREETER_HOST")

    property string password: ""
    property bool failed: false
    property bool busy: false

    // Noctalia's palette, rendered by john's Noctalia (modules/home/noctalia.nix).
    // Until it has rendered once, these are Omarchy's Tokyo Night colors.
    property var colors: ({
            background: "#1a1b26",
            wordmark: "#9ece6a",
            foreground: "#a9b1d6",
            error: "#f7768e"
        })

    FileView {
        path: Quickshell.env("GREETER_PALETTE")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.colors = Object.assign({}, root.colors, JSON.parse(text()));
            } catch (e) {
                console.warn("greeter: bad palette:", e);
            }
        }
    }

    // The logo is a file of its own (GREETER_LOGO): this file is copied to the
    // store alone, so it can't read anything next to it.
    property string logo: ""
    FileView {
        path: Quickshell.env("GREETER_LOGO")
        onLoaded: root.logo = text().replace(/\n+$/, "")
    }

    // The logo is quadrant block characters. Each character is a 2x2 grid
    // (top left, top right, bottom left, bottom right), and each quadrant
    // is twice as tall as it is wide, like a terminal cell's. Filled
    // quadrants are joined into runs along each row, so the logo needs only
    // a few hundred Rectangles.
    readonly property var quadrants: ({
            "█": "1111",
            "▀": "1100",
            "▄": "0011",
            "▌": "1010",
            "▐": "0101",
            "▘": "1000",
            "▝": "0100",
            "▖": "0010",
            "▗": "0001",
            "▚": "1001",
            "▞": "0110",
            "▛": "1110",
            "▜": "1101",
            "▙": "1011",
            "▟": "0111"
        })
    readonly property var logoArt: {
        const lines = logo.length > 0 ? logo.split("\n") : [];
        const runs = [];
        let columns = 0;
        for (let y = 0; y < lines.length * 2; y++) {
            const line = Array.from(lines[Math.floor(y / 2)]);
            columns = Math.max(columns, line.length * 2);
            let start = -1;
            for (let x = 0; x <= line.length * 2; x++) {
                const bits = quadrants[line[Math.floor(x / 2)]] || "0000";
                const filled = x < line.length * 2 && bits[(y % 2) * 2 + x % 2] === "1";
                if (filled && start < 0) {
                    start = x;
                } else if (!filled && start >= 0) {
                    runs.push({
                        x: start,
                        y: y,
                        length: x - start
                    });
                    start = -1;
                }
            }
        }
        return {
            runs: runs,
            columns: columns,
            rows: lines.length * 2
        };
    }

    // "Welcome back!" in a 5x7 pixel font drawn with Rectangles, so the
    // greeter needs no pixel font package. Only the letters it uses.
    readonly property string welcome: "Welcome back!"
    readonly property var glyphs: ({
            "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
            "e": [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."],
            "l": [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
            "c": [".....", ".....", ".###.", "#....", "#....", "#...#", ".###."],
            "o": [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
            "m": [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#...#", "#...#"],
            " ": ["...", "...", "...", "...", "...", "...", "..."],
            "b": ["#....", "#....", "#.##.", "##..#", "#...#", "#...#", "####."],
            "a": [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
            "k": ["#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#."],
            "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."]
        })

    // The animation is a few timers over shared state, which every screen
    // draws. None of it touches the keyboard: the password can be typed
    // from the first frame.
    property int shown: 0 // letters typed out so far
    property bool cursorOn: true
    // Which letter the ripple is on; out of range is the pause. It starts
    // where no letter is lifted, so nothing hops while typing.
    property int ripple: -2

    Timer {
        interval: 90
        repeat: true
        running: root.shown < root.welcome.length
        onTriggered: root.shown++
    }
    Timer {
        interval: 450
        repeat: true
        running: root.shown < root.welcome.length
        onTriggered: root.cursorOn = !root.cursorOn
    }
    // Once typed, a hop runs through the letters, then rests for about 3 s.
    Timer {
        interval: 90
        repeat: true
        running: root.shown === root.welcome.length
        onTriggered: root.ripple = (root.ripple + 1) % (root.welcome.length + 35)
    }

    function submit() {
        if (busy || password.length === 0)
            return;
        if (!Greetd.available) {
            console.warn("greeter: no greetd socket");
            fail();
            return;
        }
        busy = true;
        Greetd.createSession(user);
    }

    function fail() {
        failed = true;
        busy = false;
        password = "";
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.password);
            } else if (error) {
                console.warn("greeter:", message);
            }
        }
        function onAuthFailure(message) {
            root.fail();
        }
        function onError(error) {
            console.warn("greeter: greetd error:", error);
            Greetd.cancelSession();
            root.fail();
        }
        // Greetd starts the session once this process, and with it the
        // greeter's niri, has exited; launch() quits Quickshell.
        function onReadyToLaunch() {
            Greetd.launch([root.session], ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=niri", "XDG_CURRENT_DESKTOP=niri"]);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            // Only one surface can hold the keyboard. The others draw the same
            // screen from the shared state above.
            readonly property bool typing: modelData === Quickshell.screens[0]

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "greeter"
            WlrLayershell.keyboardFocus: typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: root.colors.background

            // Full size on screens at least 1200 px tall; smaller ones shrink
            // the logo and the letters to fit.
            readonly property real fit: Math.min(1, height / 1200)
            readonly property int px: Math.max(3, Math.round(7 * fit))
            readonly property int quadrant: Math.max(2, Math.round(5 * fit))

            Item {
                anchors.fill: parent
                focus: win.typing

                // No text field: like Omarchy's hidden TextInput, keys only
                // add to or clear the password, which is never drawn.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submit();
                    } else if (event.key === Qt.Key_Escape) {
                        root.password = "";
                    } else if (event.key === Qt.Key_Backspace) {
                        root.password = root.password.slice(0, -1);
                    } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && !root.busy) {
                        root.password += event.text;
                        root.failed = false;
                    }
                    event.accepted = true;
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 40

                // Drawn as pixel runs rather than as text: Text leaves thin
                // seams between the block characters.
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.logoArt.columns * win.quadrant
                    height: root.logoArt.rows * 2 * win.quadrant

                    Repeater {
                        model: root.logoArt.runs

                        Rectangle {
                            required property var modelData

                            x: modelData.x * win.quadrant
                            y: modelData.y * 2 * win.quadrant
                            width: modelData.length * win.quadrant
                            height: 2 * win.quadrant
                            color: root.colors.wordmark
                        }
                    }
                }

                Row {
                    id: welcome
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: win.px

                    Repeater {
                        model: root.welcome.length

                        // Letters not yet typed keep their place, so the line
                        // doesn't shift while it types.
                        Item {
                            id: letter

                            required property int index
                            readonly property var rows: root.glyphs[root.welcome[index]]
                            readonly property int columns: rows[0].length
                            // 2 pixels up for the letter the ripple is on, 1 for
                            // its neighbours, in whole pixels.
                            readonly property int lift: Math.max(0, 2 - Math.abs(root.ripple - index))

                            width: columns * win.px
                            height: 7 * win.px
                            transform: Translate {
                                y: -letter.lift * win.px
                            }

                            Repeater {
                                model: letter.index < root.shown ? letter.columns * 7 : 0

                                Rectangle {
                                    required property int index
                                    readonly property int column: index % letter.columns
                                    readonly property int line: Math.floor(index / letter.columns)

                                    visible: letter.rows[line][column] === "#"
                                    x: column * win.px
                                    y: line * win.px
                                    width: win.px
                                    height: win.px
                                    color: letter.lift === 2 ? root.colors.wordmark : root.colors.foreground
                                }
                            }

                            // A block cursor on the next letter while typing.
                            Rectangle {
                                visible: letter.index === root.shown && root.cursorOn
                                width: 5 * win.px
                                height: 7 * win.px
                                color: root.colors.wordmark
                            }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Row {
                        id: prompt
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 15

                        readonly property color accent: root.failed ? root.colors.error : root.colors.foreground

                        // Omarchy's lock.png, drawn: a shackle over a body with a keyhole.
                        Item {
                            width: 34
                            height: 38
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                x: 7
                                width: 20
                                height: 24
                                radius: 10
                                color: "transparent"
                                border.width: 4
                                border.color: prompt.accent
                            }
                            Rectangle {
                                y: 15
                                width: 34
                                height: 23
                                radius: 4
                                color: prompt.accent

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 4
                                    height: 9
                                    radius: 2
                                    color: root.colors.background
                                }
                            }
                        }

                        Rectangle {
                            width: 286
                            height: 48
                            radius: 3
                            color: "transparent"
                            border.width: 2
                            border.color: prompt.accent

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Repeater {
                                    model: Math.min(root.password.length, 21)

                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: root.colors.foreground
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.host
                        color: root.colors.foreground
                        opacity: 0.6
                        font.family: "Maple Mono"
                        font.pixelSize: 16
                        font.letterSpacing: 2
                    }
                }
            }
        }
    }
}
