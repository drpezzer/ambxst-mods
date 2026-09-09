pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.modules.services
import qs.modules.theme
import qs.config

/**
 * The screen shown on the physical monitors while the Steam Deck is playing.
 *
 * --- Why this is a layer surface and not a WlSessionLock -------------------
 *
 * The real lockscreen (shell.qml's sessionLock) is a WlSessionLock, which is
 * the right tool for locking a session: the compositor itself guarantees
 * nothing shows through. But a session lock covers EVERY output, and one of
 * the outputs here is the virtual display the Deck is streaming - it would
 * black out the game.
 *
 * So this is an overlay layer surface instantiated only on the physical
 * screens, leaving the headless output untouched and rendering the game
 * normally. The trade is real and worth stating plainly: a layer surface is
 * not a compositor-enforced lock. It takes an exclusive keyboard grab and
 * covers the screen, but it is a client surface, and if the shell were killed
 * the desktop would be exposed. It is a "don't touch my desk while I'm out"
 * screen, not a security boundary. Anyone wanting the real thing should use
 * the normal lockscreen and not stream at the same time.
 */
Variants {
    id: root

    // Physical outputs only. The Deck's virtual display must keep rendering the
    // game, so it is excluded by name.
    //
    // Two spellings have to be excluded. Hyprland auto-names outputs from
    // `output create headless` as HEADLESS-N, which is what this used to be the
    // only check for. Since the move to Sunshine the output is created with a
    // FIXED name instead - "sunshine", set in hyprland.lua and matched by
    // DECK_OUTPUT in steamdeck_mode.sh - because Sunshine resolves output_name
    // once at startup and an incrementing N is not a stable target.
    //
    // Missing the second spelling is not cosmetic: the lock surface covers the
    // very output being captured, so the Deck streams the lockscreen instead of
    // the game while the desk sits dark.
    readonly property string deckOutput: "sunshine"

    model: Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS-") && s.name !== root.deckOutput)

    PanelWindow {
        id: surface

        required property var modelData

        screen: modelData
        visible: SteamDeckService.active && SteamDeckService.armed

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "ambxst:steamdeck-lock"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "black"

        // Everything is laid out against a 1440p reference so the composition
        // is the same size on the ultrawide and the 4K TV.
        readonly property real contentScale: (screen?.height ?? 1440) / 1440

        // Only the monitor the pointer was last on gets the text and the
        // password field; the others stay plain black. Showing the prompt on
        // three monitors at once looks broken, and it is the same choice the
        // main lockscreen makes.
        readonly property bool primary: Config.lockscreen.screen
            ? modelData.name === Config.lockscreen.screen
            : modelData.name === (Quickshell.screens[0]?.name ?? "")

        Item {
            anchors.centerIn: parent
            visible: surface.primary && opacity > 0
            width: parent.width
            height: contentColumn.implicitHeight

            // Fades to nothing over the black background 30s after the last
            // input, and back the instant anything is touched. This IS the
            // "screen off" state: DPMS on this OLED drops the DisplayPort link
            // and cannot be reliably woken, so the panel stays powered and
            // simply shows black - unlit pixels either way, but instant to wake.
            opacity: SteamDeckService.displaysAwake ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutQuart
                }
            }

            Column {
                id: contentColumn

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28 * surface.contentScale

                // The Deck, drawn big. Same vector as the notch button.
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 200 * surface.contentScale
                    height: 200 * surface.contentScale

                    Image {
                        id: deckArt

                        anchors.fill: parent
                        source: Icons.steamdeck
                        sourceSize.width: 400
                        sourceSize.height: 400
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: deckArt
                        colorization: 1
                        // Dim while nothing is streaming, so the screen reads as
                        // "waiting" at a glance from across the room.
                        colorizationColor: SteamDeckService.streaming
                            ? Colors.primary
                            : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.45)

                        Behavior on colorizationColor {
                            ColorAnimation {
                                duration: 400
                                easing.type: Easing.OutQuart
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    width: surface.width * 0.8
                    wrapMode: Text.WordWrap

                    text: SteamDeckService.streaming
                        ? `You're currently playing ${SteamDeckService.gameName} on your Steam Deck`
                        : "Waiting for Steam Deck connection"

                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 34 * surface.contentScale
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter

                    text: pam.failed
                        ? "Incorrect password"
                        : "Type your password to unlock the computer"

                    color: pam.failed ? Colors.error : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.6)
                    font.family: Config.theme.font
                    font.pixelSize: 18 * surface.contentScale
                }

                // Password field. Deliberately a row of dots rather than a
                // TextField: nothing here needs editing beyond backspace, and
                // it keeps the buffer out of any focus/IME machinery.
                Rectangle {
                    id: pwdField

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 340 * surface.contentScale
                    height: 56 * surface.contentScale
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: pam.failed
                        ? Colors.error
                        : Qt.rgba(1, 1, 1, pam.busy ? 0.35 : 0.15)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 10 * surface.contentScale
                        visible: pam.buffer.length > 0 && !pam.busy

                        Repeater {
                            model: Math.min(pam.buffer.length, 16)

                            Rectangle {
                                width: 9 * surface.contentScale
                                height: width
                                radius: width / 2
                                color: Colors.overBackground
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: pam.buffer.length === 0 && !pam.busy
                        text: "● ● ●"
                        color: Qt.rgba(1, 1, 1, 0.18)
                        font.pixelSize: 12 * surface.contentScale
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: pam.busy
                        text: "Checking…"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Config.theme.font
                        font.pixelSize: 16 * surface.contentScale
                    }

                    // Shake on a rejected password, matching the main lockscreen.
                    SequentialAnimation {
                        id: shake

                        NumberAnimation { target: pwdField; property: "anchors.horizontalCenterOffset"; to: 12; duration: 50 }
                        NumberAnimation { target: pwdField; property: "anchors.horizontalCenterOffset"; to: -12; duration: 100 }
                        NumberAnimation { target: pwdField; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Unlocking leaves Steamdeck Mode running — the desk re-locks after 5 minutes idle"
                    color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.35)
                    font.family: Config.theme.font
                    font.pixelSize: 14 * surface.contentScale
                }
            }
        }

        // Any pointer movement over the surface lights the desk back up. This is
        // the wake path: the surface covers the screen and DPMS powers the
        // output rather than the input devices, so motion arrives here normally
        // while the monitors are dark.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            // No cursor while the desk is dark and locked; there is nothing to
            // point at, and a visible pointer over the password screen just
            // looks like the desktop is reachable.
            cursorShape: Qt.BlankCursor

            onPositionChanged: SteamDeckService.wakeDisplays()
            onPressed: SteamDeckService.wakeDisplays()
            onEntered: SteamDeckService.wakeDisplays()
        }

        // Keys land on the surface itself rather than on a focused item, so the
        // buffer cannot be lost if focus moves between the per-screen surfaces.
        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                // Wake first, so the very keystroke that starts the password is
                // also what brings the screen up to show it being typed.
                SteamDeckService.wakeDisplays();
                pam.handleKey(event);
            }
        }

        // --- PAM ------------------------------------------------------------
        //
        // Reuses the main lockscreen's pam.d/passwd, so this is the same
        // account password with the same lockout rules, not a second secret.
        QtObject {
            id: pam

            property string buffer: ""
            property bool busy: passwd.active
            property bool failed: false

            function handleKey(event) {
                if (passwd.active)
                    return;

                if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                    if (buffer.length > 0)
                        passwd.start();
                } else if (event.key === Qt.Key_Backspace) {
                    buffer = (event.modifiers & Qt.ControlModifier) ? "" : buffer.slice(0, -1);
                } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
                    failed = false;
                    buffer += event.text;
                }
            }
        }

        PamContext {
            id: passwd

            config: "passwd"
            configDirectory: Quickshell.shellPath("modules/lockscreen/cae/assets/pam.d")

            onResponseRequiredChanged: {
                if (!responseRequired)
                    return;
                respond(pam.buffer);
                pam.buffer = "";
            }

            onCompleted: res => {
                if (res === PamResult.Success) {
                    pam.failed = false;
                    pam.buffer = "";
                    SteamDeckService.unlock();
                    return;
                }
                pam.failed = true;
                pam.buffer = "";
                shake.start();
            }
        }

        // Clear any half-typed password whenever the screen comes back up, so a
        // buffer from the last wake never carries into the next one.
        onVisibleChanged: {
            if (visible) {
                pam.buffer = "";
                pam.failed = false;
            }
        }
    }
}
