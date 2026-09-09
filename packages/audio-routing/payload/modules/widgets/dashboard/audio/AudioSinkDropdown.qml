pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

/**
 * Compact output picker. Used both for a per-app route and for the
 * EasyEffects target device in the panel titlebar.
 */
StyledRect {
    id: root

    property list<var> sinks: []
    property var currentSink: null
    // App rows name EasyEffects with the device it feeds ("EasyEffects
    // (Speakers)"); the EasyEffects picker itself lists plain devices.
    property bool routeLabels: true
    // Compact device names ("Front Headphones") for tight spots like the titlebar.
    property bool shortLabels: false
    property string tooltip: ""
    property string placeholder: "—"
    // Sits on an already-highlighted row (the master output), so it needs the
    // inverse container to stay readable.
    property bool emphasized: false
    // Container style when idle. The titlebar copy uses "common" so it reads as
    // part of the action-button group next to it.
    property string baseVariant: "internalbg"

    signal sinkPicked(var sink)

    function labelFor(sink) {
        if (root.routeLabels)
            return AudioRouting.routeLabel(sink);
        return root.shortLabels ? AudioRouting.shortSinkLabel(sink) : AudioRouting.sinkLabel(sink);
    }

    implicitWidth: 150
    implicitHeight: 30

    variant: mouseArea.containsMouse ? "focus" : (root.emphasized ? "overprimary" : root.baseVariant)
    radius: Styling.radius(-2)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        Text {
            text: AudioRouting.sinkIcon(root.currentSink)
            font.family: Icons.font
            font.pixelSize: Styling.fontSize(-2)
            color: root.item
        }

        Text {
            Layout.fillWidth: true
            text: root.currentSink ? root.labelFor(root.currentSink) : root.placeholder
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-3)
            color: root.item
            elide: Text.ElideRight
        }

        Text {
            text: Icons.caretDown
            font.family: Icons.font
            font.pixelSize: Styling.fontSize(-4)
            color: root.item
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            sinkMenu.items = root.sinks.map(sink => ({
                        text: root.labelFor(sink),
                        icon: AudioRouting.sinkIcon(sink),
                        onTriggered: () => root.sinkPicked(sink)
                    }));
            sinkMenu.popup(root, 0, root.height + 4);
        }
    }

    StyledToolTip {
        visible: mouseArea.containsMouse && root.tooltip !== ""
        tooltipText: root.tooltip
    }

    OptionsMenu {
        id: sinkMenu
    }
}
