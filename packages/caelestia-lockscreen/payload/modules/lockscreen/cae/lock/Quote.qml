pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.lockscreen.cae.services

// A fortune in the bottom-left corner, drawn once per lock rather than on a
// timer - it should not change under you while you are typing.
LockText {
    id: root

    required property real contentScale

    text: ""
    visible: text !== ""

    color: Qt.alpha(Colours.palette.m3tertiary, 0.82)
    font.pixelSize: Math.round(26 * contentScale)
    wrapMode: Text.WordWrap
    width: Math.round(760 * contentScale)

    Component.onCompleted: fortune.running = true

    Process {
        id: fortune

        command: ["bash", Quickshell.shellPath("modules/lockscreen/cae/lock/lock_fortune.sh"), "--raw"]

        stdout: StdioCollector {
            onStreamFinished: root.text = text.trim()
        }
    }
}
