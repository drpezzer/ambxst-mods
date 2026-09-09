pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.lockscreen.cae.services

// The lockscreen composition: a centred stack of clock, date, avatar and
// password field over the blurred desktop, with a now-playing line pinned to
// the top and a quote to the bottom left.
//
// Caelestia's weather, fetch, resources and notification panels were removed
// deliberately - this is modelled on a deliberately minimal hyprlock config.
Item {
    id: root

    required property var lock

    // Every offset below is in pixels against a 1440p reference height, the way
    // the hyprlock config this mirrors lays things out, so the composition keeps
    // its proportions on the 4K screen.
    readonly property real contentScale: (lock.screen?.height ?? 1440) / 1440

    // Behind everything else.
    Bands {
        anchors.fill: parent
    }

    Center {
        anchors.fill: parent

        contentScale: root.contentScale
        lock: root.lock
    }

    NowPlaying {
        anchors.top: parent.top
        anchors.topMargin: Math.round(50 * root.contentScale)
        anchors.horizontalCenter: parent.horizontalCenter

        contentScale: root.contentScale
    }

    Quote {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.round(70 * root.contentScale)
        anchors.bottomMargin: Math.round(70 * root.contentScale)

        contentScale: root.contentScale
        active: root.lock.reveal > 0
    }
}
