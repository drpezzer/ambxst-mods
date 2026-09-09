pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.components.effects
import qs.modules.lockscreen.cae.services
import qs.modules.lockscreen.cae.utils

// Circular avatar with a solid ring and a thin halo outside it. AnimatedImage
// rather than Image because ~/.face.icon (what Ambxst's avatar picker writes) is
// often a GIF.
Item {
    id: root

    property int implicitSize: 208
    // Ring thickness and the gap out to the halo, from the hyprlock layout.
    readonly property int border: Math.round(4 * implicitSize / 208)
    readonly property int haloGap: Math.round(8 * implicitSize / 208)

    implicitWidth: implicitSize + haloGap * 2
    implicitHeight: implicitWidth

    // Thin halo ring sitting just outside the avatar's own border.
    Rectangle {
        anchors.fill: parent

        color: "transparent"
        radius: width / 2
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
    }

    // Doubles as the mask for the image above. It has to stay visible with its
    // own layer: an invisible item paints nothing and would hand the mask effect
    // an empty texture, leaving the avatar blank.
    //
    // Opaque `palette`, not `tPalette`. Mask multiplies the mask's alpha into the
    // image, and tPalette's surface roles carry Caelestia's transparency.layers
    // alpha (~0.4), so the photo was drawn at roughly half opacity over the
    // blurred desktop and read as dimmed and desaturated. Only maskSpreadAtMin's
    // soft ramp kept it visible at all - the 0.5 threshold should have cut an
    // alpha that low entirely.
    Rectangle {
        id: disc

        anchors.centerIn: parent

        implicitWidth: root.implicitSize - root.border * 2
        implicitHeight: implicitWidth
        radius: width / 2
        color: Colours.palette.m3surfaceContainerHighest

        layer.enabled: true
    }

    MaterialIcon {
        anchors.centerIn: parent

        text: "person"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.size(Math.round(root.implicitSize / 2.5)).build()
        visible: pfp.status !== Image.Ready
    }

    AnimatedImage {
        id: pfp

        anchors.fill: disc

        source: `file://${Paths.home}/.face.icon`
        fillMode: Image.PreserveAspectCrop

        layer.enabled: true
        layer.effect: Mask {
            maskSource: disc
        }
    }

    // Drawn last so it sits over the image's edge.
    Rectangle {
        anchors.centerIn: parent

        implicitWidth: root.implicitSize
        implicitHeight: implicitWidth
        radius: width / 2
        color: "transparent"
        border.width: root.border
        border.color: Colours.palette.m3primary
    }
}
