pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.widgets.dashboard.controls
import qs.config

/**
 * Per-application audio output routing.
 *
 * The notch is a fixed size, so everything below the header lives in a single
 * scrolling column rather than growing the panel.
 */
Item {
    id: root

    Component.onCompleted: AudioRouting.initialize()

    // Pipewire only fills in `properties` and `description` for nodes that are
    // actively bound, and routing needs both: object.serial to address a
    // stream, and the description to label a device.
    //
    // Only the sinks this tab can actually offer are bound. Binding every
    // device pulls in the whole wall of `.pro-output-` profiles, which costs a
    // round trip each and warns on every one of them, since their channel maps
    // do not match their channel volumes.
    PwObjectTracker {
        objects: (Audio.outputAppNodes ?? []).concat(Audio.inputAppNodes ?? []).concat(AudioRouting.selectableSinks ?? []).concat(AudioRouting.selectableSources ?? [])
    }

    onVisibleChanged: {
        if (visible)
            AudioRouting.refresh();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        PanelTitlebar {
            id: titlebar
            Layout.fillWidth: true
            title: "Audio Outputs"

            // Which device EasyEffects feeds. Everything routed to EasyEffects
            // shares this one destination, since it mixes them into one stream.
            // A Row is a positioner, so children are aligned by matching their
            // height rather than by anchors, which QML forbids here.
            Row {
                spacing: 6

                Text {
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    text: "EasyEffects"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Medium
                    // Dimmed while nothing is routed through EasyEffects, so an
                    // idle processor is not mistaken for an active one.
                    color: AudioRouting.easyeffectsInUse ? Colors.overSurfaceVariant : Colors.outline

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation {
                            duration: Config.animDuration
                        }
                    }
                }

                AudioSinkDropdown {
                    width: 130
                    height: 28
                    sinks: AudioRouting.easyeffectsTargetSinks
                    currentSink: AudioRouting.easyeffectsTarget
                    routeLabels: false
                    shortLabels: true
                    baseVariant: "common"
                    placeholder: "Output"
                    tooltip: {
                        if (AudioRouting.easyeffectsRestarting)
                            return "Restarting EasyEffects…";
                        if (!AudioRouting.easyeffectsInUse)
                            return "Nothing is routed through EasyEffects right now. This is where it will output when something is.";
                        return "Device EasyEffects outputs to (changing it restarts EasyEffects)";
                    }
                    opacity: AudioRouting.easyeffectsRestarting ? 0.5 : (AudioRouting.easyeffectsInUse ? 1 : 0.65)
                    enabled: !AudioRouting.easyeffectsRestarting
                    onSinkPicked: sink => AudioRouting.setEasyEffectsTarget(sink)

                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration
                        }
                    }
                }
            }

            actions: [
                {
                    icon: Icons.faders,
                    tooltip: "Open EasyEffects",
                    onClicked: function () {
                        EasyEffectsService.openApp();
                    }
                },
                {
                    icon: Icons.popOpen,
                    tooltip: "Open PipeWire Volume Control",
                    onClicked: function () {
                        Quickshell.execDetached(["pavucontrol"]);
                    }
                }
            ]
        }

        // Two conditions worth explaining inline: EasyEffects silently undoing
        // per-app routes, and the restart it needs to change its own output.
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: notice.implicitHeight + 16
            visible: AudioRouting.easyeffectsCapturing || AudioRouting.easyeffectsRestarting
            variant: "internalbg"
            radius: Styling.radius(-2)

            RowLayout {
                id: notice
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Text {
                    text: AudioRouting.easyeffectsRestarting ? Icons.faders : Icons.info
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(0)
                    color: AudioRouting.easyeffectsRestarting ? Styling.srItem("overprimary") : Colors.warning
                    Layout.alignment: Qt.AlignTop
                }

                Text {
                    Layout.fillWidth: true
                    // The installer turns this off; the message covers a
                    // later EasyEffects reinstall or a manual re-enable.
                    text: AudioRouting.easyeffectsRestarting ? "Restarting EasyEffects to move its output. Anything routed through it will drop out for a moment." : "EasyEffects is set to process every output stream, which undoes individual routes. Turn off \"Process all output streams\" in its preferences."
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
        }

        Flickable {
            id: flickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: flickable.contentHeight > flickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            ColumnLayout {
                id: column
                width: flickable.width
                spacing: 6

                // Master row: moves the default sink and every live stream. Its
                // slider drives the hardware device the default route ends at —
                // the EasyEffects virtual sink's own volume is never applied,
                // so volume always belongs to a real device. While apps are
                // split across devices there is no single volume or output, so
                // the slider yields to the per-device rows below.
                AudioRouteRow {
                    Layout.fillWidth: true
                    isMaster: true
                    label: "All programs"
                    glyph: Icons.speakerHigh
                    sinks: AudioRouting.masterSinks
                    currentSink: AudioRouting.splitRouting ? null : AudioRouting.currentMasterSink()
                    placeholder: "Multiple outputs"
                    volumeNode: AudioRouting.splitRouting ? null : AudioRouting.masterVolumeSink
                    onSinkPicked: sink => AudioRouting.routeAll(sink)
                }

                // Per-device volume, shown once apps are split across outputs:
                // each row is every stream ending at that device (directly or
                // through EasyEffects), with the device's volume as the knob.
                Repeater {
                    model: AudioRouting.splitRouting ? AudioRouting.deviceGroups : []

                    delegate: AudioRouteRow {
                        required property var modelData

                        Layout.fillWidth: true
                        showDropdown: false
                        glyph: AudioRouting.sinkIcon(modelData.device)
                        label: `All through ${AudioRouting.shortSinkLabel(modelData.device)}` + (modelData.viaEe ? " · EasyEffects" : "")
                        volumeNode: modelData.device
                    }
                }

                Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                }

                Text {
                    text: "Applications"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                    Layout.topMargin: 2
                }

                Repeater {
                    model: Audio.outputAppNodes

                    delegate: AudioRouteRow {
                        required property var modelData

                        Layout.fillWidth: true
                        node: modelData
                        label: Audio.appNodeDisplayName(modelData)
                        sinks: AudioRouting.selectableSinks

                        // `properties` is empty until the tracker finishes binding
                        // the node, so both of these have to re-run on `ready`
                        // rather than only once when the row is created. Reading
                        // streamSinks makes the binding re-run on every refresh.
                        iconName: modelData.ready ? AudioRouting.appIconName(modelData) : ""

                        currentSink: {
                            const map = AudioRouting.streamSinks;
                            return modelData.ready ? AudioRouting.sinkForStream(modelData) : null;
                        }
                        onSinkPicked: sink => AudioRouting.routeApp(modelData, sink)
                    }
                }

                Text {
                    visible: (Audio.outputAppNodes ?? []).length === 0
                    text: "No applications are playing audio"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.outline
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 16
                }

                Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                }

                Text {
                    text: "Recording"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                    Layout.topMargin: 2
                }

                // Same shape as playback, driven by source-outputs: the master
                // row is the default microphone, app rows are whatever is
                // recording right now.
                AudioRouteRow {
                    Layout.fillWidth: true
                    isMaster: true
                    label: "All programs"
                    glyph: Icons.mic
                    isInput: true
                    sinks: AudioRouting.masterSources
                    currentSink: AudioRouting.currentMasterSource()
                    volumeNode: AudioRouting.masterVolumeSource
                    onSinkPicked: source => AudioRouting.routeAllInputs(source)
                }

                Repeater {
                    model: Audio.inputAppNodes

                    delegate: AudioRouteRow {
                        required property var modelData

                        Layout.fillWidth: true
                        node: modelData
                        isInput: true
                        label: Audio.appNodeDisplayName(modelData)
                        sinks: AudioRouting.selectableSources
                        iconName: modelData.ready ? AudioRouting.appIconName(modelData) : ""

                        currentSink: {
                            const map = AudioRouting.streamSources;
                            return modelData.ready ? AudioRouting.sourceForStream(modelData) : null;
                        }
                        onSinkPicked: source => AudioRouting.routeAppInput(modelData, source)
                    }
                }
            }
        }
    }
}
