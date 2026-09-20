pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ambxst Roadie (drpezzer.roadie): what the brightness service learned over
// DDC, remembered for the rest of the session.
//
// Every shell start, Brightness.qml runs `ddcutil detect` to find which I2C bus
// is which monitor and then reads each monitor's brightness with `ddcutil
// getvcp`. DDC traffic blocks the display driver while it is on the wire: on an
// NVIDIA desktop with two DDC monitors that froze the compositor's main loop
// for 1.2 s in total (measured against Hyprland's request socket: stalls of
// 288, 331, 207 and 335 ms) two seconds into every reload, under the shell's own
// entrance -- a lag spike on every screen, in every application.
//
// Bus numbers cannot change within a boot unless the set of monitors does, and
// the shell itself is what sets the brightness. So the detect result and the
// levels are kept in $XDG_RUNTIME_DIR (gone at logout, so never stale across a
// boot), keyed by the monitors that are connected, and a reload uses them
// instead of asking again. A changed monitor set, a wake from suspend and
// `ambxst brightness -r` still go to the hardware.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-roadie-ddc.json"
    property var data: ({ key: "", monitors: [], levels: {} })
    readonly property bool enabled: RoadieSettings.ddcCache

    function screensKey() {
        const parts = [];
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++)
            parts.push(String(screens[i].name) + "|" + String(screens[i].model || ""));
        parts.sort();
        return parts.join(";");
    }

    // The detect result for the monitors connected right now, or null.
    function cachedMonitors() {
        if (!root.enabled || !root.data.key || root.data.key !== root.screensKey())
            return null;
        const m = root.data.monitors;
        return (Array.isArray(m) && m.length > 0) ? m : null;
    }
    function storeMonitors(monitors) {
        root.data = { key: root.screensKey(), monitors: monitors, levels: root.data.levels || {} };
        root.write();
    }
    function level(busNum) {
        if (!root.enabled || root.data.key !== root.screensKey())
            return null;
        const l = (root.data.levels || {})[String(busNum)];
        return (l && l.max > 0) ? l : null;
    }
    function storeLevel(busNum, cur, max) {
        if (!busNum || !(max > 0))
            return;
        const levels = Object.assign({}, root.data.levels || {});
        const old = levels[String(busNum)];
        if (old && old.cur === cur && old.max === max)
            return;
        levels[String(busNum)] = { cur: cur, max: max };
        root.data = { key: root.data.key, monitors: root.data.monitors, levels: levels };
        writeTimer.restart();
    }
    function invalidate() {
        root.data = { key: "", monitors: [], levels: {} };
        root.write();
    }

    function write() {
        file.setText(JSON.stringify(root.data));
    }
    Timer {
        id: writeTimer
        interval: 400
        onTriggered: root.write()
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    Component.onCompleted: {
        file.waitForJob();
        if (!file.loaded)
            return;
        try {
            const o = JSON.parse(file.text());
            if (o && typeof o === "object" && Array.isArray(o.monitors))
                root.data = { key: String(o.key || ""), monitors: o.monitors, levels: o.levels || {} };
        } catch (e) {}
    }
}
