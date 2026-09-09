import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.services

StyledRect {
    id: root

    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
    radius: Tokens.rounding.extraLargeIncreased
    implicitHeight: header.anchors.margins + header.implicitHeight + Tokens.spacing.medium + layout.implicitHeight + layout.anchors.bottomMargin

    RowLayout {
        id: header

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Tokens.padding.largeIncreased

        spacing: Tokens.spacing.small

        MaterialIcon {
            Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
            text: "schedule"
            fontStyle: Tokens.font.icon.builders.medium.weight(title.font.weight).build()
        }

        StyledText {
            id: title

            text: qsTr("Hourly forecast")
            font: Tokens.font.title.medium
        }
    }

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.largeIncreased
        anchors.margins: Tokens.padding.large

        spacing: Tokens.spacing.small

        Repeater {
            model: CUtils.clamp(Math.floor((layout.width + layout.spacing) / (Tokens.sizes.lock.forecastItemWidth + layout.spacing)), 0, Weather.hourlyForecast.length)

            ColumnLayout {
                id: hour

                required property int index
                readonly property var cond: Weather.hourlyForecast[index]

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                // The petal turns, the temperature sits still. They have to be
                // siblings for that: as a child it would need counter-rotating,
                // and a child's centre lands a rounded pixel or so off its
                // parent's, which the turn then swings it around -- upright,
                // but visibly bouncing once per revolution.
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: petal.implicitSize
                    implicitHeight: petal.implicitSize

                    MaterialShape {
                        id: petal

                        anchors.centerIn: parent
                        implicitSize: temp.implicitHeight + Tokens.padding.medium * 2
                        shape: MaterialShape.Cookie4Sided
                        color: Qt.alpha(Colours.palette.m3primary, hour.index === 0 ? 1 : 0)

                        Behavior on color {
                            CAnim {}
                        }

                        // Only the current hour's petal is filled in, so only it
                        // spins.
                        RotationAnimation on rotation {
                            running: hour.index === 0 && petal.visible
                            from: 0
                            to: 360
                            duration: 30000
                            loops: Animation.Infinite
                        }
                    }

                    StyledText {
                        id: temp

                        anchors.centerIn: parent
                        text: Weather.formatTemp(hour.cond.tempC).slice(0, -1) // Remove C/F
                        color: hour.index === 0 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        font: Tokens.font.title.medium
                    }
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: hour.cond.icon
                    color: Colours.palette.m3secondary
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: hour.cond.precipChance + "%"
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.extraSmall
                    Layout.alignment: Qt.AlignHCenter
                    text: hour.index === 0 ? qsTr("Now") : Qt.formatDateTime(new Date(hour.cond.timestamp.replace("T", " ")), GlobalConfig.services.useTwelveHourClock ? "ha" : "hh:00")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }
        }
    }
}
