pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ambxst Roadie (drpezzer.roadie): every option of the mod, in one file of
// its own -- ~/.config/ambxst/roadie.json -- behind Settings > Roadie.
//
// Read synchronously at start (waitForJob), so the first frame already has
// the user's values: whether to animate the shell in, whether to lock after
// boot and the rest used to arrive a second or more into the start through
// the mod manager's async settings call. The file holds only what differs
// from the defaults and is watched, so a hand edit applies live.
//
// Everything Roadie changes has a MODE: "roadie" (its own animation, with the
// duration beside it), "stock" (what plain Ambxst does there) and, where that
// is a different thing, "immediate" (it simply happens). Stock and immediate
// coincide for the shell start, the reload and the fullscreen frame -- upstream
// does not animate those at all -- so those offer roadie / stock only. A
// duration of 0 on `barSlideDuration` and `frameDuration` means "automatic"
// (derived from Ambxst's animation speed, see BarContent), which is what they
// ship as. The bug fixes (stranded bar, stale fullscreen detection, corners over
// a game on an unfocused monitor, hotplug) have no mode: nobody wants those back.
//
// Values set in Settings > Mods before 1.1.0 (the mod manager's
// mods/drpezzer.roadie.json) are imported once, the first time this file is
// missing.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst/roadie.json"
    readonly property string legacyPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst/mods/drpezzer.roadie.json"

    readonly property var defaults: ({
        // behaviour
        followFocus: true,      // stock: false
        notifyFollowFocus: true, // stock: false
        veilEnabled: true,      // stock: false
        ddcCache: true,         // stock: false (ask the monitors again on every start)
        osd: "quiet",           // quiet | stock | off
        bootLock: "auto",       // auto | always | never (stock: never)
        farewellSource: false,
        farewellHold: 1500,
        // modes
        enterMode: "roadie",      // roadie | stock
        leaveMode: "roadie",      // roadie | stock
        barSlideMode: "roadie",   // roadie | stock | immediate
        frameMode: "roadie",      // roadie | stock
        farewellMode: "roadie",   // roadie | stock (no farewell) | immediate
        notchCoverMode: "roadie", // roadie | stock: the notch over a fullscreen window
        // durations (ms) of the roadie modes
        enterDuration: 650,
        leaveDuration: 900,
        barSlideDuration: 0,   // 0 = automatic
        frameDuration: 0,      // 0 = automatic
        farewellDuration: 900
    })

    readonly property var modeChoices: ({
        enterMode: ["roadie", "stock"],
        leaveMode: ["roadie", "stock"],
        barSlideMode: ["roadie", "stock", "immediate"],
        frameMode: ["roadie", "stock"],
        farewellMode: ["roadie", "stock", "immediate"],
        notchCoverMode: ["roadie", "stock"]
    })

    // Plain Ambxst everywhere (the fixes stay).
    readonly property var stockValues: ({
        followFocus: false,
        notifyFollowFocus: false,
        veilEnabled: false,
        ddcCache: false,
        osd: "stock",
        bootLock: "never",
        enterMode: "stock",
        leaveMode: "stock",
        barSlideMode: "stock",
        frameMode: "stock",
        farewellMode: "stock",
        notchCoverMode: "stock"
    })

    // What the file holds (overrides only).
    property var values: ({})

    function get(key) {
        const v = root.values[key];
        return v !== undefined ? v : root.defaults[key];
    }
    function isDefault(key) {
        return root.values[key] === undefined || root.values[key] === root.defaults[key];
    }

    function mode(key) {
        const v = root.get(key);
        return (root.modeChoices[key] || []).indexOf(v) !== -1 ? v : root.defaults[key];
    }

    readonly property bool followFocus: !!root.get("followFocus")
    readonly property bool notifyFollowFocus: !!root.get("notifyFollowFocus")
    readonly property bool veilEnabled: !!root.get("veilEnabled")
    readonly property bool ddcCache: !!root.get("ddcCache")
    readonly property string osd: ["quiet", "stock", "off"].indexOf(root.get("osd")) !== -1 ? root.get("osd") : "quiet"
    readonly property string bootLock: ["auto", "always", "never"].indexOf(root.get("bootLock")) !== -1 ? root.get("bootLock") : "auto"
    readonly property bool farewellSource: !!root.get("farewellSource")
    readonly property int farewellHold: root.ms("farewellHold")

    readonly property string enterMode: root.mode("enterMode")
    readonly property string leaveMode: root.mode("leaveMode")
    readonly property string barSlideMode: root.mode("barSlideMode")
    readonly property string frameMode: root.mode("frameMode")
    readonly property string farewellMode: root.mode("farewellMode")
    readonly property string notchCoverMode: root.mode("notchCoverMode")

    readonly property int enterDuration: root.ms("enterDuration")
    readonly property int leaveDuration: root.ms("leaveDuration")
    readonly property int barSlideDuration: root.ms("barSlideDuration")
    readonly property int frameDuration: root.ms("frameDuration")
    readonly property int farewellDuration: root.ms("farewellDuration")

    function ms(key) {
        const n = Number(root.get(key));
        return (isNaN(n) || n < 0) ? root.defaults[key] : Math.min(10000, Math.round(n));
    }

    function set(key, value) {
        if (root.defaults[key] === undefined)
            return;
        const next = Object.assign({}, root.values);
        if (value === root.defaults[key] || value === undefined || value === null)
            delete next[key];
        else
            next[key] = value;
        root.values = next;
        root.write();
    }
    function reset(key) {
        root.set(key, root.defaults[key]);
    }
    function resetAll() {
        root.values = ({});
        root.write();
    }
    function stockAll() {
        root.values = Object.assign({}, root.values, root.stockValues);
        root.write();
    }
    readonly property bool allStock: {
        for (const k in root.stockValues) {
            if (root.get(k) !== root.stockValues[k])
                return false;
        }
        return true;
    }
    function write() {
        file.setText(JSON.stringify(root.values, null, 2) + "\n");
    }

    function parse(text) {
        try {
            const o = JSON.parse(text);
            const out = {};
            if (o && typeof o === "object") {
                for (const k in o) {
                    if (root.defaults[k] !== undefined && typeof o[k] === typeof root.defaults[k])
                        out[k] = o[k];
                }
            }
            return out;
        } catch (e) {
            console.warn("RoadieSettings: roadie.json is not valid JSON, using defaults:", e);
            return {};
        }
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.values = root.parse(text())
    }
    FileView {
        id: legacyFile
        path: root.legacyPath
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        file.waitForJob();
        if (file.loaded) {
            root.values = root.parse(file.text());
            return;
        }
        // First run of 1.1.0: bring over what was set in Settings > Mods.
        legacyFile.waitForJob();
        if (!legacyFile.loaded)
            return;
        let old = {};
        try {
            old = JSON.parse(legacyFile.text()) || {};
        } catch (e) {
            return;
        }
        if (old.enterAnimation === false)
            old.enterMode = "stock";
        if (old.farewellEnabled === false)
            old.farewellMode = "stock";
        const all = root.parse(JSON.stringify(old));
        const imported = {};
        for (const k in all) {
            if (all[k] !== root.defaults[k])
                imported[k] = all[k]; // only what differs from the defaults
        }
        if (Object.keys(imported).length > 0) {
            console.log("RoadieSettings: imported", Object.keys(imported).join(", "), "from Settings > Mods");
            root.values = imported;
            root.write();
        }
    }
}
