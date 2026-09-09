pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.config

// Battery level of the connected Bluetooth devices.
//
// The bar shows one device — whichever has least charge left, since that is the
// only one you need to act on. Hovering pops out the full list. With nothing
// connected, or nothing connected that reports a level, the widget removes
// itself from the layout entirely rather than sitting there empty.
Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    readonly property var lowest: BluetoothBattery.lowest
    readonly property int level: lowest?.battery ?? 0

    property bool popupOpen: devicesPopup.isOpen

    visible: BluetoothBattery.available

    Layout.preferredWidth: vertical ? 36 : buttonBg.implicitWidth
    Layout.preferredHeight: vertical ? buttonBg.implicitHeight : 36

    // Same ramp as BatteryIndicator's, so the two indicators sitting next to each
    // other never disagree about what "low" looks like.
    function levelColor(percent: int): color {
        if (percent <= 15)
            return Colors.red;
        if (percent >= 85)
            return Colors.green;
        const ratio = (percent - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    // Hover open/close, both delayed: a short arm on the way in so sweeping the
    // pointer along the bar doesn't flash the panel open, and a shorter one on the
    // way out so a pixel of jitter at the button's edge doesn't shut it.
    onIsHoveredChanged: {
        if (root.isHovered) {
            closeTimer.stop();
            openTimer.restart();
        } else {
            openTimer.stop();
            closeTimer.restart();
        }
    }

    // The widget can vanish under an open popout — the last device disconnects,
    // or the bar hides — and the popout is drawn by another window, so it would
    // be left behind with nothing to point at.
    onVisibleChanged: {
        if (!visible) {
            openTimer.stop();
            closeTimer.stop();
            devicesPopup.close();
        }
    }

    Timer {
        id: openTimer
        interval: 250
        onTriggered: {
            if (root.isHovered && root.visible)
                devicesPopup.open();
        }
    }

    Timer {
        id: closeTimer
        interval: 150
        onTriggered: devicesPopup.close()
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        topLeftRadius: root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.endRadius

        // Rounded: these come off text metrics, and a fractional bar widget puts
        // its own popout half a pixel off the grid (see BarPopout.currentAnchor).
        implicitWidth: root.vertical ? 36 : Math.round(rowLayout.implicitWidth) + 20
        implicitHeight: root.vertical ? Math.round(columnLayout.implicitHeight) + 14 : 36

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        RowLayout {
            id: rowLayout
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: Icons.bluetoothDeviceIcon(root.lowest?.icon ?? "")
                font.family: Icons.font
                font.pixelSize: 16
                color: root.popupOpen ? buttonBg.item : Colors.overBackground
            }

            Text {
                text: root.level + "%"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.bold: true
                color: root.popupOpen ? buttonBg.item : root.levelColor(root.level)
            }
        }

        ColumnLayout {
            id: columnLayout
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 1

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Icons.bluetoothDeviceIcon(root.lowest?.icon ?? "")
                font.family: Icons.font
                font.pixelSize: 16
                color: root.popupOpen ? buttonBg.item : Colors.overBackground
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                // No "%" here: the column is 36px wide and the glyph above already
                // says what the number is about.
                text: root.level
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.bold: true
                color: root.popupOpen ? buttonBg.item : root.levelColor(root.level)
            }
        }

        // No MouseArea: this widget is a readout, and the Bluetooth button a few
        // slots up already owns connecting, disconnecting and blueman-manager.
    }

    // Device list — a floating pill next to the bar, or grown out of the frame
    // when the bar is contained by it. See BarPopout.
    BarPopout {
        id: devicesPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 8

        Item {
            implicitWidth: 236
            // Fixed per row rather than derived from the column, so the panel
            // doesn't expand into place on first open.
            implicitHeight: Math.max(1, BluetoothBattery.devices.length) * 44 + Math.max(0, BluetoothBattery.devices.length - 1) * 4

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: BluetoothBattery.devices

                    delegate: StyledRect {
                        id: deviceRow
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 44

                        // The one the bar is showing gets the accent, so it's
                        // obvious which row the number outside came from.
                        readonly property bool isLowest: modelData.address === (BluetoothBattery.lowest?.address ?? "")

                        variant: isLowest ? "primary" : "common"
                        enableShadow: false
                        // Nests inside the popout's own corners; see BarPopout.contentRadius.
                        radius: devicesPopup.contentRadius

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: Icons.bluetoothDeviceIcon(deviceRow.modelData.icon)
                                font.family: Icons.font
                                font.pixelSize: 18
                                color: deviceRow.item
                            }

                            Text {
                                Layout.fillWidth: true
                                text: deviceRow.modelData.name
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: deviceRow.item
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: deviceRow.modelData.batteryAvailable
                                text: Icons.batteryLevelIcon(deviceRow.modelData.battery)
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: deviceRow.item
                            }

                            Text {
                                // A connected device that reports no level still
                                // belongs in the list; it just has nothing to say.
                                text: deviceRow.modelData.batteryAvailable ? deviceRow.modelData.battery + "%" : "—"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: deviceRow.item
                                opacity: deviceRow.modelData.batteryAvailable ? 1 : 0.6
                            }
                        }
                    }
                }
            }
        }
    }
}
