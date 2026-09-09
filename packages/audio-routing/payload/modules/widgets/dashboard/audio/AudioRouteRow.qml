pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

/**
 * One routing row: [app icon] (app name) [output dropdown], with a volume
 * slider underneath.
 *
 * Used for both an individual app stream and the "All programs" master row,
 * which differ only in the sinks offered, what picking one does, and whether
 * the slider drives the stream or the default sink.
 */
Item {
    id: root

    // The app stream this row routes. Null for the master row.
    property var node: null
    // Node whose volume the slider drives. Defaults to the routed stream; the
    // master row points it at the default sink so the slider is system volume.
    property var volumeNode: null
    // Sink currently in use, resolved by the caller so the row stays dumb.
    property var currentSink: null
    property list<var> sinks: []

    property bool isMaster: false
    property string label: ""
    property string iconName: ""
    // Phosphor glyph, used by the master row instead of a desktop icon.
    property string glyph: ""
    // Device-group rows are volume-only; routing them is ambiguous when their
    // members arrive via different paths (direct vs through EasyEffects).
    property bool showDropdown: true
    // Shown when currentSink is null — the master row uses it while apps are
    // split across devices and there is no single answer.
    property string placeholder: "—"
    // Recording rows swap the speaker glyph set for microphones.
    property bool isInput: false

    signal sinkPicked(var sink)

    // The master row sits on a filled container, so its contents take that
    // variant's item colour rather than the plain over-background one.
    readonly property color contentColor: root.isMaster ? Styling.srItem("primary") : Colors.overBackground
    readonly property color accentColor: root.isMaster ? Styling.srItem("primary") : Styling.srItem("overprimary")

    readonly property var audioNode: root.volumeNode ?? root.node
    readonly property bool hasVolume: !!(root.audioNode?.ready && root.audioNode?.audio)
    readonly property bool muted: root.audioNode?.audio?.muted ?? false
    readonly property real volume: root.audioNode?.audio?.volume ?? 0

    function toggleMute() {
        if (root.audioNode?.audio)
            root.audioNode.audio.muted = !root.audioNode.audio.muted;
    }

    implicitHeight: content.implicitHeight + 12
    implicitWidth: parent?.width ?? 320

    StyledRect {
        anchors.fill: parent
        variant: root.isMaster ? "primary" : (hover.hovered ? "focus" : "common")
        radius: Styling.radius(4)
    }

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Icon: a desktop-entry image for apps, a themed glyph for the master row.
            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22

                // Same treatment as the dock, systray and launcher: resolve through
                // the icon image provider, then recolor to the matugen palette so
                // app icons sit in the theme instead of fighting it. Tinted takes
                // the Image over as a shader source and hides it itself, so the
                // Image must stay visible and the wrapper does the hiding.
                Item {
                    id: iconWrap
                    anchors.fill: parent
                    visible: !root.isMaster && root.iconName !== "" && appIcon.status === Image.Ready

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: root.iconName !== "" ? "image://icon/" + root.iconName : ""
                        sourceSize.width: 44
                        sourceSize.height: 44
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                    }

                    Tinted {
                        anchors.fill: appIcon
                        sourceItem: appIcon
                        fullTint: true
                    }
                }

                // Covers the master row and any app whose icon could not be resolved.
                Text {
                    anchors.centerIn: parent
                    visible: !iconWrap.visible
                    text: root.glyph !== "" ? root.glyph : Icons.speakerHigh
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(2)
                    color: root.isMaster ? root.contentColor : Styling.srItem("overprimary")
                }
            }

            // App name
            Text {
                Layout.fillWidth: true
                text: root.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: root.isMaster ? Font.Bold : Font.Normal
                color: root.contentColor
                elide: Text.ElideRight
            }

            // Output dropdown
            AudioSinkDropdown {
                visible: root.showDropdown
                Layout.preferredWidth: 168
                Layout.preferredHeight: 30
                sinks: root.sinks
                currentSink: root.currentSink
                emphasized: root.isMaster
                placeholder: root.placeholder
                tooltip: root.isMaster ? "Output for every program" : `${root.label} → ${AudioRouting.routeLabel(root.currentSink)}`
                onSinkPicked: sink => root.sinkPicked(sink)
            }
        }

        // Volume. Collapsed rather than disabled when the node has no audio
        // (yet), so a half-bound stream does not show a dead slider at zero.
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.hasVolume

            // Mute toggle, aligned under the app icon.
            Text {
                id: muteButton
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (root.isInput)
                        return root.muted ? Icons.micSlash : Icons.mic;
                    if (root.muted)
                        return Icons.speakerSlash;
                    if (root.volume < 0.01)
                        return Icons.speakerNone;
                    return root.volume < 0.5 ? Icons.speakerLow : Icons.speakerHigh;
                }
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: root.muted ? Colors.error : (muteArea.containsMouse ? root.accentColor : root.contentColor)

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration / 2
                    }
                }

                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMute()
                }

                StyledToolTip {
                    visible: muteArea.containsMouse
                    tooltipText: root.muted ? "Unmute" : "Mute"
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                value: root.volume
                // The row lives in a Flickable; a scrollable slider would eat
                // the wheel events the list needs.
                scroll: false
                progressColor: root.muted ? Colors.outline : root.accentColor
                backgroundColor: root.isMaster ? Qt.alpha(root.contentColor, 0.25) : Colors.surfaceBright

                // Routed through Audio so the shell-wide ear-bang protection
                // applies here too.
                onValueChanged: {
                    if (root.hasVolume && Math.abs(value - root.volume) > 0.001)
                        Audio.setNodeVolume(root.audioNode, value);
                }

                Behavior on progressColor {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration / 2
                    }
                }
            }

            // Fixed width so the slider does not resize as the number changes.
            Text {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: `${Math.round(root.volume * 100)}%`
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: root.muted ? Colors.outline : root.contentColor
            }
        }
    }
}
