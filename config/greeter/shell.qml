// Login screen, a Quickshell greeter on greetd (modules/nixos/greeter.nix).
// The look is Omarchy's SDDM theme (default/sddm/omarchy/Main.qml in
// basecamp/omarchy): a wordmark over a lock and an outlined password box that
// shows one bullet per character, both turning red after a wrong password.
// As there, the user and the session are fixed, so there is nothing to pick.
// The wordmark is the hostname instead of Omarchy's logo.
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

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Quickshell.env("GREETER_HOST")
                    color: root.colors.wordmark
                    font.family: "Maple Mono"
                    font.pixelSize: 120
                    font.weight: Font.Black
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 8
                }

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
            }
        }
    }
}
