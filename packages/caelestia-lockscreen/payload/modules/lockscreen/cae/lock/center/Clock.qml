pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Caelestia.Config
import qs.modules.lockscreen.cae.services

// One serif line, e.g. "19:28". Caelestia stacked the hours and minutes in two
// weights; this composition wants a single centred time.
Item {
    id: root

    required property real contentScale

    implicitWidth: time.implicitWidth
    // Trimmed to the glyphs' own height so the 360px offset in Center.qml lands
    // on the digits rather than on the font's line box.
    implicitHeight: metrics.tightBoundingRect.height

    LockText {
        id: time

        y: -(metrics.tightBoundingRect.y - metrics.boundingRect.y)

        text: Time.format(GlobalConfig.services.useTwelveHourClock ? "h:mm" : "HH:mm")
        font.pixelSize: Math.round(150 * root.contentScale)
        font.weight: Font.Medium

        TextMetrics {
            id: metrics

            text: time.text
            font: time.font
        }
    }
}
