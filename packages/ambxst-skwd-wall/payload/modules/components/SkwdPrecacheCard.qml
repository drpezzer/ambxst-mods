import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.theme
import qs.modules.services

// Ambxst Skwd-wall: manages pre-cached screen-resolution assets for
// zero-stutter, instant Vulkan wallpaper transitions.
StyledRect {
    id: precacheCard
    implicitHeight: precacheRow.implicitHeight + 24
    Layout.preferredHeight: implicitHeight
    variant: "pane"
    radius: Styling.radius(4)

    readonly property bool busy: SkwdWall.precacheState === "running"
    readonly property bool allCached: SkwdWall.precacheTotal > 0 && SkwdWall.precacheCount >= SkwdWall.precacheTotal

    Component.onCompleted: {
        SkwdWall.refreshPrecacheStatus();
    }

    RowLayout {
        id: precacheRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
        spacing: 12

        Text {
            Layout.alignment: Qt.AlignTop
            text: Icons.sparkle
            font.family: Icons.font
            font.pixelSize: 22
            color: Styling.srItem("overprimary")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: "Fast Transitions Pre-caching"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Bold
                color: Colors.overBackground
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (precacheCard.busy)
                        return "Optimizing wallpapers… (" + SkwdWall.precacheCount + " / " + SkwdWall.precacheTotal + ") " + SkwdWall.precachePercent + "%";
                    if (SkwdWall.precacheTotal > 0)
                        return SkwdWall.precacheCount + " of " + SkwdWall.precacheTotal + " wallpapers optimized (" + SkwdWall.precacheSizeMb + " MB)";
                    return "Pre-scales wallpapers to your screen resolution for instant transitions with zero visual stutter.";
                }
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.outline
                wrapMode: Text.WordWrap
            }

            // Progress bar when running
            Rectangle {
                visible: precacheCard.busy
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                Layout.topMargin: 4
                radius: 2
                color: Colors.surfaceContainerHighest

                Rectangle {
                    height: parent.height
                    width: Math.max(8, parent.width * Math.min(1.0, SkwdWall.precachePercent / 100.0))
                    radius: 2
                    color: Styling.srItem("overprimary")

                    Behavior on width {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        }

        // Action Buttons Row
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // Clear Cache button (subtle)
            StyledRect {
                id: clearBtn
                visible: !precacheCard.busy && SkwdWall.precacheCount > 0
                Layout.preferredHeight: 32
                Layout.preferredWidth: clearLabel.implicitWidth + 20
                variant: maClear.containsMouse ? "common" : "transparent"
                radius: Styling.radius(2)

                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Clear"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.outline
                }

                MouseArea {
                    id: maClear
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SkwdWall.clearPrecache()
                }
            }

            // Main Optimize Button
            StyledRect {
                id: precacheActionBtn
                Layout.preferredHeight: 34
                Layout.preferredWidth: precacheActionLabel.implicitWidth + 28
                variant: precacheCard.busy ? "common" : (maPrecacheAction.containsMouse ? "primaryfocus" : "primary")
                radius: Styling.radius(2)
                opacity: precacheCard.busy ? 0.7 : 1.0

                Text {
                    id: precacheActionLabel
                    anchors.centerIn: parent
                    text: {
                        if (precacheCard.busy)
                            return "Optimizing…";
                        if (precacheCard.allCached)
                            return "Re-optimize";
                        return "Optimize Library";
                    }
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Bold
                    color: precacheCard.busy ? Colors.overSurface : Styling.srItem(maPrecacheAction.containsMouse ? "primaryfocus" : "primary")
                }

                MouseArea {
                    id: maPrecacheAction
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !precacheCard.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SkwdWall.runPrecache()
                }
            }
        }
    }
}
