pragma ComponentBehavior: Bound

import "center"
import QtQuick
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.services

// Clock, date, avatar and password field, each positioned as an absolute offset
// from screen centre rather than stacked in a column, so the spacing matches the
// hyprlock layout this is modelled on exactly.
Item {
    id: root

    required property var lock
    required property real contentScale

    readonly property int avatarSize: Math.round(208 * contentScale)
    readonly property int fieldWidth: Math.round(440 * contentScale)

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round(-360 * root.contentScale)

        contentScale: root.contentScale
        lock: root.lock
    }

    ScrambleText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round(-180 * root.contentScale)

        source: Time.format("dddd, d MMMM")
        active: root.lock.reveal > 0
        font.pixelSize: Math.round(40 * root.contentScale)
    }

    ProfilePic {
        anchors.centerIn: parent

        implicitSize: root.avatarSize
    }

    PasswordInput {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round(190 * root.contentScale)

        centerScale: Math.max(0.8, root.contentScale)
        centerWidth: root.fieldWidth
        lock: root.lock
    }

    StateMessage {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round(300 * root.contentScale)

        width: parent.width
        pam: root.lock.pam
    }
}
