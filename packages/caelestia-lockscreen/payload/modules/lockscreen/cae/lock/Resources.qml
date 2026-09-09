pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import Caelestia.Services
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.components.effects
import qs.modules.lockscreen.cae.services
// Every Ambxst import here is qualified, and must stay that way: both module
// sets export a StyledRect (this file's root type) and both a Config, so an
// unqualified import silently rebinds them to the wrong one -- which builds
// and even renders, then fails to instantiate as a lock surface.
import qs.config as Ambxst
import qs.modules.components as Ambxst
import qs.modules.theme as Ambxst

StyledRect {
    id: root

    readonly property real fontScale: {
        const diff = width / 391 - 1; // 391 is the width at 1080 height screen
        return 1 + Math.pow(Math.abs(diff), 0.8) * Math.sign(diff);
    }

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    // This panel sits in the card's top-right corner, so that corner has to
    // follow the card's outer curve like the other three do (weather uses the
    // same value top-left, the notif dock does it bottom-right).
    topRightRadius: Tokens.rounding.extraExtraLarge
    color: Colours.tPalette.m3surfaceContainer

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        Resource {
            icon: "memory"
            value: Math.round(Cpu.percentage * 100) + "%"
            fillValue: Cpu.percentage
            colour: Ambxst.Colors.red

            // Rides alongside the icon rather than in a bubble of its own: the
            // only reading here that needs a second number, and the dials read
            // as a set when nothing hangs off one of them. No C/F suffix, which
            // is what Ambxst's own metrics readout does.
            note: {
                const temp = Cpu.temperature;
                const useF = GlobalConfig.services.useFahrenheitPerformance;
                return `${Math.ceil(useF ? temp * 1.8 + 32 : temp)}°`;
            }
            noteColour: Cpu.temperature > 90 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        }

        Resource {
            icon: "memory_alt"
            value: Math.round(Memory.percentage * 100) + "%"
            fillValue: Memory.percentage
            colour: Ambxst.Colors.cyan
        }

        Resource {
            icon: "hard_disk"
            value: Math.round(Storage.percentage * 100) + "%"
            fillValue: Storage.percentage
            colour: Ambxst.Colors.yellow
        }
    }

    // A dial: the value sweeps clockwise around the top half of a disc, drawn
    // with the same wavy arc Ambxst uses for the media player's seek ring and
    // the volume/brightness sliders.
    component Resource: Item {
        id: res

        required property string icon
        required property string value
        required property color colour
        property real fillValue: 0

        // Optional second reading, shown next to the icon.
        property string note: ""
        property color noteColour: Colours.palette.m3onSurfaceVariant

        readonly property real level: Math.max(0, Math.min(1, fillValue))

        // Stroke width of the dial, and the gap from it to the item's edge.
        readonly property real ring: Math.max(3, Math.round(width * 0.055))
        readonly property real dialRadius: width / 2 - ring

        Layout.fillWidth: true
        implicitHeight: width

        // Read-only, so `enabled: false` drops the drag handling; everything
        // else about it is the media player's ring.
        Ambxst.CircularSeekBar {
            id: dial

            anchors.fill: parent
            enabled: false

            value: res.level
            startAngleDeg: 180 // 9 o'clock, sweeping clockwise over the top
            spanAngleDeg: 180

            accentColor: res.colour
            trackColor: Colours.palette.m3outlineVariant

            lineWidth: res.ring
            ringPadding: res.ring
            // No handle: there is nothing to drag on a gauge. A bead covers the
            // seam instead, and the break is sized to sit under it.
            showHandle: false
            showJunctionDot: true
            junctionDotSize: res.ring * 1.7
            handleSpacing: res.ring * 1.2

            wavy: Ambxst.Config.performance.wavyLine
            // Both scale with the reading, like the volume/mic/brightness
            // sliders: flat at rest, tightening as the vital climbs.
            waveAmplitude: res.ring * 0.4 * res.level
            // The frequency is in cycles per radian, so a fixed value would
            // bunch up on these dials -- they are less than a third the media
            // player ring's radius. Solved for its ~20px wavelength instead.
            waveFrequency: Math.max(8, Math.round(2 * Math.PI * res.dialRadius / 20)) * res.level
        }

        // Inset far enough to clear the dial's stroke.
        MaterialShape {
            id: shape

            anchors.centerIn: parent
            shape: MaterialShape.Circle
            implicitSize: Math.round(res.width - res.ring * 5)

            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 1)
            opacity: Colours.tPalette.m3surfaceContainerHigh.a
            layer.enabled: true
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: -Tokens.spacing.extraSmall

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: res.icon
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.medium.scale(root.fontScale * 0.85).build()
                }

                StyledText {
                    visible: res.note !== ""
                    text: res.note
                    color: res.noteColour
                    font: Tokens.font.body.builders.medium.scale(root.fontScale * 0.85).width(50).build()

                    Behavior on color {
                        CAnim {}
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: res.value
                color: res.colour
                font: Tokens.font.headline.builders.large.scale(root.fontScale * 0.85).width(50).build()
            }
        }

        Behavior on fillValue {
            Anim {}
        }
    }
}
