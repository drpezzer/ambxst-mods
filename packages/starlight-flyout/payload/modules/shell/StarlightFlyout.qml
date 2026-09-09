pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.config

// Starlight render-queue flyout (LOCAL PATCH, not upstream Ambxst).
//
// Same construction as BluetoothFlyout: drawn inside UnifiedShellPanel with
// the frame's own "bg" variant plus concave fillets, so it reads as the top
// frame band bulging downward — the notch's language. It lives at the
// top-right of the screen and is completely invisible until the pointer
// enters a hotzone over the frame band there; then it springs out (OutBack
// overshoot) with three controls: play (resume), pause, stop (cancel).
// Buttons call ~/.local/bin/topaz-starlight-ctl, which owns the real logic
// (and also answers topaz-pause/-resume/-cancel from a tty).
//
// The whole thing only exists while ~/.local/state/topaz-starlight/state
// exists ("running" | "paused") — that file is written by topaz-starlight,
// survives reboots, and is deleted on queue completion or cancel, which is
// what finally retires the hotzone.
Item {
    id: root

    required property ShellScreen targetScreen
    // Thickness of the top frame band; the panel hangs from its inner edge.
    required property int frameInset

    // Handed to UnifiedShellPanel's input mask.
    property alias hitbox: unionArea
    property alias hotzone: hotzoneArea

    // Main-OLED only: UnifiedShellPanel instantiates one per screen, but the
    // hotzone/poll should live on a single display.
    readonly property bool onMain: targetScreen && targetScreen.name === "DP-1"

    // "" (no queue), "running" or "paused" — polled from disk.
    property string queueState: ""
    readonly property bool queueActive: onMain && queueState !== ""

    readonly property bool active: queueActive && (hotzoneHover.hovered || panelHover.hovered)

    readonly property int filletSize: Styling.radius(4)
    readonly property int panelRadius: Styling.radius(4)
    readonly property int fillet: filletSize
    readonly property int contentPadding: 6
    // Keeps clear of the frame's rounded corner while staying "top right".
    readonly property int cornerMargin: 56

    readonly property int openWidth: 3 * 44 + 2 * 4 + contentPadding * 2
    readonly property int openHeight: 46

    readonly property real panelW: openWidth
    property real panelH: active ? openHeight : 0

    // The notch's signature: overshoot on the way out, settle on the way in.
    Behavior on panelH {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: root.active ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.active ? 1.2 : 1.0
        }
    }

    readonly property real panelX: root.width - cornerMargin - panelW
    readonly property real panelY: frameInset

    // Held alive for the length of the close animation (see BluetoothFlyout).
    property bool renderVisible: false

    onActiveChanged: {
        if (active) {
            hideTimer.stop();
            renderVisible = true;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Config.animDuration > 0 ? Config.animDuration + 60 : 60
        onTriggered: root.renderVisible = false
    }

    // Poll the state file (2 s): covers create, edit and delete, and is cheap
    // enough to run forever. cat on a missing file -> empty string.
    Process {
        id: stateProc
        command: ["cat", Quickshell.env("HOME") + "/.local/state/topaz-starlight/state"]
        stdout: StdioCollector {
            onStreamFinished: root.queueState = text.trim()
        }
        stderr: StdioCollector {}
    }

    Timer {
        interval: 2000
        running: root.onMain
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!stateProc.running)
                stateProc.running = true;
        }
    }

    function ctl(action) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/topaz-starlight-ctl", action]);
        // Snappy feedback; the poll corrects us if the ctl disagreed.
        if (action === "pause")
            queueState = "paused";
        else if (action === "resume")
            queueState = "running";
    }

    // Invisible reveal strip over the top frame band at the corner. Input only
    // ever reaches it via the mask, which gates on queueActive.
    Item {
        id: hotzoneArea
        x: root.panelX - root.fillet - 24
        y: 0
        width: root.panelW + root.fillet * 2 + 24 + root.cornerMargin
        height: root.frameInset + 4

        HoverHandler {
            id: hotzoneHover
        }
    }

    // Union of the panel and its two fillets — everything the mask carves from.
    Item {
        id: unionArea

        x: root.panelX - root.fillet
        y: root.panelY
        width: root.panelW + root.fillet * 2
        height: root.panelH

        visible: root.renderVisible

        readonly property real px: root.fillet
        readonly property real trailAlong: root.fillet + root.panelW

        HoverHandler {
            id: panelHover
        }

        // Swallows clicks so they don't fall through to whatever is behind.
        MouseArea {
            anchors.fill: parent
        }

        // Continuous with the frame band above it, so it takes the same
        // Background variant; the silhouette comes from the mask.
        StyledRect {
            id: panelFill
            anchors.fill: parent
            variant: "bg"
            radius: 0
            enableBorder: false
            enableShadow: false

            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: panelMask
                maskThresholdMin: 0.5
                maskThresholdMax: 1.0
                maskSpreadAtMin: 1.0
            }
        }

        // Silhouette: panel body plus the two concave flares back into the frame.
        Item {
            id: panelMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true

            Rectangle {
                x: unionArea.px
                y: 0
                width: root.panelW
                height: root.panelH
                color: "white"
                // Top corners square (merged with the frame), bottom rounded.
                bottomLeftRadius: root.panelRadius
                bottomRightRadius: root.panelRadius
            }

            // Leading flare, left of the panel, hugging the frame edge.
            RoundCorner {
                x: 0
                y: 0
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: RoundCorner.CornerEnum.TopRight
            }

            // Trailing flare, right of the panel.
            RoundCorner {
                x: unionArea.trailAlong
                y: 0
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: RoundCorner.CornerEnum.TopLeft
            }
        }

        // ── Contents ──────────────────────────────────────────────────────
        Item {
            id: contentRoot
            x: unionArea.px
            y: 0
            width: root.panelW
            height: root.panelH
            clip: true

            scale: root.active ? 1.0 : 0.8
            opacity: root.active ? 1.0 : 0.0
            visible: opacity > 0

            Behavior on scale {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: [
                        { glyph: Icons.play, action: "resume", lit: root.queueState === "paused" },
                        { glyph: Icons.pause, action: "pause", lit: root.queueState === "running" },
                        { glyph: Icons.stop, action: "cancel", lit: false }
                    ]

                    delegate: Item {
                        id: button
                        required property var modelData
                        implicitWidth: 44
                        implicitHeight: 34

                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(10)
                            color: buttonArea.containsMouse
                                ? Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.14)
                                : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            font.family: Icons.font
                            font.pixelSize: 16
                            text: button.modelData.glyph
                            color: button.modelData.lit ? Colors.primary : Colors.overBackground
                        }

                        MouseArea {
                            id: buttonArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ctl(button.modelData.action)
                        }
                    }
                }
            }
        }
    }
}
