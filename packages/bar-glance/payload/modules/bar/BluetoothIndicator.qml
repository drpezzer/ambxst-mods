pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.config

// Bar button for Bluetooth. The panel itself is drawn by UnifiedShellPanel
// (see BluetoothFlyout) so it can merge into the frame; this only owns the
// button and reports where the panel should sprout from.
Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    readonly property string screenName: bar.screen?.name ?? ""
    readonly property bool panelOpen: GlobalStates.bluetoothPanelVisible && GlobalStates.bluetoothPanelScreenName === root.screenName

    Layout.preferredWidth: 36
    Layout.preferredHeight: 36
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    Component.onCompleted: BluetoothService.initialize()

    onIsHoveredChanged: {
        BluetoothControl.buttonHovered = isHovered;
        if (isHovered)
            hoverOpenTimer.restart();
        else
            hoverOpenTimer.stop();
    }

    // Hover opens the panel after a short dwell, so brushing past the icon on
    // the way to another widget doesn't pop it. Click still toggles, and the
    // panel closes itself once the pointer leaves both it and the button
    // (BluetoothControl.leaveTimer).
    Timer {
        id: hoverOpenTimer
        interval: 300
        onTriggered: {
            if (root.isHovered && !root.panelOpen)
                BluetoothControl.openPanel(root.screenName, root.currentAnchor());
        }
    }

    // Where the panel should sprout from, along the bar axis, in panel
    // coordinates. Read at click time: mapToItem isn't a bindable dependency, so
    // as a property binding this would silently go stale.
    function currentAnchor(): real {
        const p = buttonBg.mapToItem(null, 0, 0);
        return root.vertical ? p.y : p.x;
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledRect {
        id: buttonBg
        variant: root.panelOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.panelOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: {
                if (!BluetoothService.enabled)
                    return Icons.bluetoothOff;
                return BluetoothService.connected ? Icons.bluetoothConnected : Icons.bluetooth;
            }
            font.family: Icons.font
            font.pixelSize: 18
            // Matugen accent rather than the near-white foreground the other bar
            // widgets default to, and muted when the adapter is off.
            color: {
                if (root.panelOpen)
                    return buttonBg.item;
                return BluetoothService.enabled ? Colors.primary : Colors.overSurfaceVariant;
            }

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    // Full manager for the things the flyout deliberately doesn't
                    // do — pairing wizards, adapter settings, file transfer.
                    // Close ours first so it isn't left hanging behind the window.
                    BluetoothControl.closePanel();
                    Quickshell.execDetached(["blueman-manager"]);
                    return;
                }
                BluetoothControl.toggle(root.screenName, root.currentAnchor());
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.panelOpen
            tooltipText: {
                if (!BluetoothService.enabled)
                    return "Bluetooth: off";
                if (BluetoothService.connectedDevices > 0)
                    return `Bluetooth: ${BluetoothService.connectedDevices} connected`;
                return "Bluetooth: on";
            }
        }
    }
}
