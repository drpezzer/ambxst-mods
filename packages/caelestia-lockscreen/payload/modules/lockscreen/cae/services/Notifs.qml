pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.modules.services

// Adapter presenting Ambxst's Notifications in the shape the ported lock UI
// expects.
//
// Upstream this ran its own NotificationServer, which meant the lockscreen had
// a private in-memory store: notifications raised while locked showed on the
// lock but could not be dismissed from Ambxst's notification centre afterwards,
// because they were two separate lists. Reading Ambxst's store instead makes
// the lock a view onto the same notifications the rest of the shell manages.
Singleton {
    id: root

    // Bumped periodically so relative timestamps re-evaluate while locked.
    property int tick: 0

    readonly property var list: {
        root.tick; // re-evaluate on tick
        return Notifications.list.map(n => ({
                    appName: n.appName,
                    summary: n.summary,
                    body: n.body,
                    image: n.cachedImage || n.image,
                    appIcon: n.cachedAppIcon || n.appIcon,
                    urgency: root.toUrgency(n.urgency),
                    time: n.time,
                    timeStr: root.relativeTime(n.time),
                    // Ambxst drops notifications from its list rather than
                    // flagging them, so nothing here is ever "closing".
                    closed: false,

                    // Upstream's NotifData tracked which views were holding a
                    // notification open so it would not be dismissed from under
                    // them. Ambxst owns that lifecycle, so these are no-ops --
                    // but NotifGroup calls them on create/destroy and throws
                    // without them.
                    lock: function (holder) {},
                    unlock: function (holder) {}
                }));
    }

    readonly property var notClosed: list

    // Ambxst stores urgency as a string; the lock UI compares against the
    // Quickshell enum.
    function toUrgency(urgency: string): int {
        if (urgency === "critical")
            return NotificationUrgency.Critical;
        if (urgency === "low")
            return NotificationUrgency.Low;
        return NotificationUrgency.Normal;
    }

    function relativeTime(time: real): string {
        const mins = Math.floor((Date.now() - time) / 60000);
        if (!time || mins < 1)
            return qsTr("now");
        if (mins < 60)
            return qsTr("%1m").arg(mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return qsTr("%1h").arg(hours);
        return qsTr("%1d").arg(Math.floor(hours / 24));
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.tick++
    }
}
