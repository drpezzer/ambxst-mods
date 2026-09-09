pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.services

// Now-playing line across the top. Hidden entirely when nothing is playing,
// rather than holding an empty row. The note is a Material icon rather than a
// glyph inside the serif run, which has no coverage for it.
Row {
    id: root

    required property real contentScale

    readonly property string title: Players.active?.trackTitle ?? ""
    readonly property string artist: Players.active?.trackArtist ?? ""
    readonly property color tint: Qt.alpha(Colours.palette.m3tertiary, 0.82)

    spacing: Math.round(14 * contentScale)
    visible: title !== ""
    opacity: visible ? 1 : 0

    Behavior on opacity {
        CAnim {}
    }

    MaterialIcon {
        anchors.verticalCenter: parent.verticalCenter

        text: "music_note"
        color: root.tint
        fontStyle: Tokens.font.icon.size(Math.round(30 * root.contentScale)).build()
    }

    LockText {
        anchors.verticalCenter: parent.verticalCenter

        text: root.artist ? `${root.title} - ${root.artist}` : root.title
        color: root.tint
        font.pixelSize: Math.round(30 * root.contentScale)
    }
}
