pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.components
import qs.modules.corners
import qs.modules.services
import qs.modules.theme
import qs.modules.globals
import qs.config

// Bluetooth panel, drawn inside UnifiedShellPanel next to the bar rather than in
// a popup window. Being in the same surface as ScreenFrameContent — and using the
// same "bg" variant — is what lets it read as the frame bulging out around it,
// the way the notch merges into the screen edge.
Item {
    id: root

    required property ShellScreen targetScreen
    // Distance from the screen edge to where the panel begins. When attached that
    // is the frame band's thickness, so the two fills touch with no seam; when
    // floating it clears the bar's pills instead.
    required property int frameInset
    required property string barPosition

    // With "contain bar" off the frame no longer wraps the bar — the widgets
    // become separate floating pills, so there is nothing to merge into. The
    // panel then becomes a pill of its own: fully rounded, no flares, offset off
    // the bar rather than butted against it.
    required property bool attached
    readonly property int floatGap: 8
    readonly property int edgeInset: frameInset + (attached ? 0 : floatGap)
    readonly property int fillet: attached ? filletSize : 0

    // Handed to UnifiedShellPanel's input mask.
    property alias hitbox: unionArea

    readonly property bool active: GlobalStates.bluetoothPanelVisible && GlobalStates.bluetoothPanelScreenName === root.targetScreen.name

    readonly property bool barAtLeft: barPosition === "left"
    readonly property bool barAtRight: barPosition === "right"
    readonly property bool barAtTop: barPosition === "top"
    readonly property bool barAtBottom: barPosition === "bottom"
    readonly property bool barVertical: barAtLeft || barAtRight

    // Concave corners that flare the panel back into the frame, and the rounding
    // on the far side. Matched to the frame's own inner radius.
    readonly property int filletSize: Styling.radius(4)
    readonly property int panelRadius: Styling.radius(4)

    // Collapsed, the panel is the size of the bar button it grows out of.
    readonly property int buttonSize: 36
    readonly property int contentPadding: 8
    readonly property int panelBreadth: 300

    // The panel is the same shape whichever edge it grows from: a fixed-width
    // column of rows, as tall as its contents. Only the anchoring, the collapse
    // direction and which edges get flares change with the bar's position.
    readonly property int maxSpan: Math.max(180, root.height - edgeInset - fillet * 2 - 16)
    readonly property int targetSpan: Math.min(contentColumn.implicitHeight + contentPadding * 2, maxSpan)

    readonly property int openWidth: panelBreadth
    readonly property int openHeight: targetSpan
    // Collapses along the axis it grows out of, keeping the button's size on the
    // other, so it looks like it retracts into the button.
    readonly property int shutWidth: barVertical ? 0 : buttonSize
    readonly property int shutHeight: barVertical ? buttonSize : 0

    property real panelW: active ? openWidth : shutWidth
    property real panelH: active ? openHeight : shutHeight

    // The notch's signature: overshoot on the way out, settle on the way back in.
    // This also carries span changes as devices appear, so the panel grows
    // smoothly while the scan runs.
    Behavior on panelW {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: root.active ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.active ? 1.2 : 1.0
        }
    }

    Behavior on panelH {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: root.active ? Easing.OutBack : Easing.OutQuart
            easing.overshoot: root.active ? 1.2 : 1.0
        }
    }

    // Keep the panel inside the frame no matter where along the bar the button is.
    readonly property real anchorPos: {
        const raw = GlobalStates.bluetoothPanelAnchor;
        const extent = barVertical ? panelH : panelW;
        const along = barVertical ? root.height : root.width;
        // Margin along the bar's own axis — frameInset is the thickness of the
        // perpendicular band and means nothing in this direction.
        //
        // Horizontal bars need more of it: their button sits well along the bar,
        // so the panel lands near a screen corner and a small margin leaves it
        // clinging to the edge. Vertical bars rarely run out of room this way.
        const margin = barVertical ? fillet + 8 : fillet + 40;
        return Math.max(margin, Math.min(raw, Math.max(margin, along - margin - extent)));
    }

    readonly property real panelX: {
        if (barAtLeft)
            return edgeInset;
        if (barAtRight)
            return root.width - edgeInset - panelW;
        return anchorPos;
    }

    readonly property real panelY: {
        if (barAtTop)
            return edgeInset;
        if (barAtBottom)
            return root.height - edgeInset - panelH;
        return anchorPos;
    }

    // Collapsed height is the button's, not zero, so `panelH > 0` can't decide
    // this — hold the item alive for the length of the close animation instead.
    property bool renderVisible: false
    visible: renderVisible

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

    // Union of the panel and its two fillets — everything the mask carves from.
    Item {
        id: unionArea

        x: root.barVertical ? root.panelX : root.panelX - root.fillet
        y: root.barVertical ? root.panelY - root.fillet : root.panelY
        width: root.panelW + (root.barVertical ? 0 : root.fillet * 2)
        height: root.panelH + (root.barVertical ? root.fillet * 2 : 0)

        // Local origin of the panel rect inside the union.
        readonly property real px: root.barVertical ? 0 : root.fillet
        readonly property real py: root.barVertical ? root.fillet : 0

        // The flares hug the edge the panel is attached along, which is the far
        // edge for a right or bottom bar rather than the near one.
        readonly property real flareCross: {
            if (root.barVertical)
                return root.barAtLeft ? 0 : root.panelW - root.fillet;
            return root.barAtTop ? 0 : root.panelH - root.fillet;
        }
        // Along the bar's axis: the leading flare sits before the panel, the
        // trailing one just past its far end.
        readonly property real trailAlong: root.barVertical ? py + root.panelH : px + root.panelW

        HoverHandler {
            onHoveredChanged: GlobalStates.bluetoothPanelHovered = hovered
        }

        // Swallows clicks so they don't fall through to whatever is behind.
        MouseArea {
            anchors.fill: parent
        }

        // Attached, this is literally continuous with the frame, so it takes the
        // same Background variant — anything else would show a seam where they
        // meet. Floating, it is a surface in its own right and follows Popup,
        // border included, like every other flyout in the shell.
        //
        // The radius is only set in the floating case: attached, the silhouette
        // comes from the mask (square against the frame, flared corners), and a
        // rounded StyledRect underneath would fight it. Floating, the union *is*
        // the panel, so matching the radius lets Popup's border land on the real
        // edge instead of tracing a rectangle around it.
        StyledRect {
            id: panelFill
            anchors.fill: parent
            variant: root.attached ? "bg" : "popup"
            radius: root.attached ? 0 : root.panelRadius
            enableBorder: !root.attached
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
                y: unionArea.py
                width: root.panelW
                height: root.panelH
                color: "white"

                // Floating, every corner is rounded; attached, the edge meeting
                // the frame stays square so the two fills merge.
                topLeftRadius: (!root.attached || root.barAtRight || root.barAtBottom) ? root.panelRadius : 0
                topRightRadius: (!root.attached || root.barAtLeft || root.barAtBottom) ? root.panelRadius : 0
                bottomLeftRadius: (!root.attached || root.barAtRight || root.barAtTop) ? root.panelRadius : 0
                bottomRightRadius: (!root.attached || root.barAtLeft || root.barAtTop) ? root.panelRadius : 0
            }

            // Leading flare (above the panel for a vertical bar, left of it otherwise)
            RoundCorner {
                x: root.barVertical ? unionArea.flareCross : 0
                y: root.barVertical ? 0 : unionArea.flareCross
                // Size is held constant and the flare is gated with opacity rather
                // than `visible` or a shrinking size: RoundCorner paints through a
                // Canvas, and both of those left it stale — blank after a live
                // contain-bar toggle or bar-position change until a shell restart.
                opacity: root.attached ? 1 : 0
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: {
                    if (root.barAtLeft)
                        return RoundCorner.CornerEnum.BottomLeft;
                    if (root.barAtRight)
                        return RoundCorner.CornerEnum.BottomRight;
                    if (root.barAtTop)
                        return RoundCorner.CornerEnum.TopRight;
                    return RoundCorner.CornerEnum.BottomRight;
                }
            }

            // Trailing flare (below the panel for a vertical bar, right of it otherwise)
            RoundCorner {
                x: root.barVertical ? unionArea.flareCross : unionArea.trailAlong
                y: root.barVertical ? unionArea.trailAlong : unionArea.flareCross
                // Size is held constant and the flare is gated with opacity rather
                // than `visible` or a shrinking size: RoundCorner paints through a
                // Canvas, and both of those left it stale — blank after a live
                // contain-bar toggle or bar-position change until a shell restart.
                opacity: root.attached ? 1 : 0
                size: root.filletSize
                width: root.filletSize
                height: root.filletSize
                color: "white"
                corner: {
                    if (root.barAtLeft)
                        return RoundCorner.CornerEnum.TopLeft;
                    if (root.barAtRight)
                        return RoundCorner.CornerEnum.TopRight;
                    if (root.barAtTop)
                        return RoundCorner.CornerEnum.TopLeft;
                    return RoundCorner.CornerEnum.BottomLeft;
                }
            }
        }

        // ── Contents ───────────────────────────────────────────────────────
        // Mirrors NotchAnimationBehavior so they settle like the notch's views.
        Item {
            id: contentRoot

            x: unionArea.px
            y: unionArea.py
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

            Flickable {
                anchors.fill: parent
                anchors.margins: root.contentPadding
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: contentColumn
                    // Pinned to the open width rather than the animating one, so text
                    // doesn't reflow (and the span doesn't thrash) mid-expand.
                    width: root.panelBreadth - root.contentPadding * 2
                    spacing: 6

                    // ---- Header: state + power toggle ----
                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        variant: "common"
                        enableShadow: false
                        radius: Styling.radius(0)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                text: BluetoothService.enabled ? Icons.bluetooth : Icons.bluetoothOff
                                font.family: Icons.font
                                font.pixelSize: 22
                                color: BluetoothService.enabled ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: "Bluetooth"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(0)
                                    font.bold: true
                                    color: Colors.overBackground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (!BluetoothService.enabled)
                                            return "Off";
                                        if (BluetoothService.connectedDevices > 0)
                                            return `${BluetoothService.connectedDevices} connected`;
                                        return BluetoothService.discovering ? "Scanning…" : "On";
                                    }
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            // Power switch. Driven straight off the service rather than a
                            // two-way binding, so a state refresh can't re-trigger it.
                            Item {
                                id: powerToggle
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 20

                                readonly property bool on: BluetoothService.enabled

                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: powerToggle.on ? Styling.srItem("overprimary") : Colors.surfaceBright
                                    border.color: powerToggle.on ? Styling.srItem("overprimary") : Colors.outline
                                    border.width: 1

                                    Behavior on color {
                                        enabled: Config.animDuration > 0
                                        ColorAnimation {
                                            duration: Config.animDuration / 2
                                        }
                                    }

                                    Rectangle {
                                        x: powerToggle.on ? parent.width - width - 2 : 2
                                        y: 2
                                        width: parent.height - 4
                                        height: width
                                        radius: width / 2
                                        color: powerToggle.on ? Colors.background : Colors.overSurfaceVariant

                                        Behavior on x {
                                            enabled: Config.animDuration > 0
                                            NumberAnimation {
                                                duration: Config.animDuration / 2
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Behavior on color {
                                            enabled: Config.animDuration > 0
                                            ColorAnimation {
                                                duration: Config.animDuration / 2
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BluetoothControl.setEnabled(!powerToggle.on)
                                }
                            }
                        }
                    }

                    // ---- Paired / connected ----
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: BluetoothService.enabled && BluetoothControl.knownDevices.length > 0
                        text: "My devices"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-3)
                        font.bold: true
                        color: Colors.overSurfaceVariant
                    }

                    Repeater {
                        model: BluetoothService.enabled ? BluetoothControl.knownDevices : []

                        delegate: BluetoothDeviceRow {
                            required property var modelData

                            Layout.fillWidth: true
                            device: modelData
                            onActionTaken: BluetoothControl.refreshSoon()
                        }
                    }

                    // ---- Discovered ----
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: BluetoothService.enabled && (BluetoothControl.newDevices.length > 0 || BluetoothService.discovering)
                        spacing: 6

                        Text {
                            text: "Available"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-3)
                            font.bold: true
                            color: Colors.overSurfaceVariant
                        }

                        Text {
                            id: scanSpinner
                            visible: BluetoothService.discovering
                            text: Icons.circleNotch
                            font.family: Icons.font
                            font.pixelSize: 11
                            color: Colors.overSurfaceVariant

                            RotationAnimator on rotation {
                                running: scanSpinner.visible
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    Repeater {
                        model: BluetoothService.enabled ? BluetoothControl.newDevices : []

                        delegate: BluetoothDeviceRow {
                            required property var modelData

                            Layout.fillWidth: true
                            device: modelData
                            onActionTaken: BluetoothControl.refreshSoon()
                        }
                    }

                    // ---- Empty states ----
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        visible: !BluetoothService.enabled || (BluetoothControl.knownDevices.length === 0 && BluetoothControl.newDevices.length === 0)
                        text: BluetoothService.enabled ? "Searching for devices…" : "Bluetooth is off"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }
            }
        }
    }
}
