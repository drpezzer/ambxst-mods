pragma ComponentBehavior: Bound

import ".."
import QtQuick
import qs.modules.lockscreen.cae.services
import qs.config as Ambxst

// One serif line, e.g. "19:28". Caelestia stacked the hours and minutes in two
// weights; this composition wants a single centred time.
Item {
    id: root

    required property real contentScale

    implicitWidth: time.implicitWidth
    // Trimmed to the glyphs' own height so the 360px offset in Center.qml lands
    // on the digits rather than on the font's line box.
    implicitHeight: metrics.tightBoundingRect.height

    ScrambleText {
        id: time

        y: -(metrics.tightBoundingRect.y - metrics.boundingRect.y)

        // Follows Ambxst's own clock setting (bar.use12hFormat) rather than
        // Caelestia's, so the lock and the bar always agree.
        source: Time.format(Ambxst.Config.bar.use12hFormat ? "h:mm" : "HH:mm")
        font.pixelSize: Math.round(150 * root.contentScale)
        font.weight: Font.Medium

        // Measured on the real string, not the scrambling one, so the layout
        // does not jitter while katakana stand in for the digits.
        TextMetrics {
            id: metrics

            text: time.source
            font: time.font
        }
    }
}
