pragma Singleton
import QtQuick
import Quickshell
import qs.modules.services

// roadie: which screen the notch shows a notification on.
//
// Stock Ambxst pops every notification in every screen's notch at once. With
// "notifications follow the focused screen" on, one screen is chosen:
//
//   - the focused screen, normally;
//   - if a fullscreen window covers the focused screen and another screen is
//     free, that one -- the screen focus was on last if it qualifies, else the
//     first free one -- so the game is never interrupted while there is
//     somewhere else to look;
//   - with a single screen, or every screen covered, the focused screen after
//     all: better a popup over the game than a notification nobody sees
//     (the bell in the dashboard silences them if that is a bother).
//
// Only screens that have a shell panel count (each UnifiedShellPanel reports
// its screen here, so a screen left out of bar.screenList is never chosen --
// it has no notch to pop anything in), and only while they are connected. A
// focused screen without a panel counts as covered. An empty target means
// "every screen", which is also the answer whenever the focused screen is
// unknown or nothing has registered yet, so nothing is ever lost to a gap in
// the data.
Singleton {
    id: root

    // Screen name -> true while a fullscreen window covers it. A key exists for
    // every screen with a live shell panel.
    property var covered: ({})

    function setCovered(name, isCovered) {
        if (!name)
            return;
        if ((name in root.covered) && root.covered[name] === !!isCovered)
            return;
        const next = Object.assign({}, root.covered);
        next[name] = !!isCovered;
        root.covered = next;
    }

    // A panel going away. Skipped while its screen is still connected: a
    // panel recreated for the same screen may have reported already (a
    // hot-plug rebuilds panels before the old ones are torn down), and the
    // stale entry of a screen that is really gone is filtered out below.
    function forget(name) {
        if (!name || !(name in root.covered) || root.connectedNames.indexOf(name) !== -1)
            return;
        const next = Object.assign({}, root.covered);
        delete next[name];
        root.covered = next;
    }

    readonly property string focusedName: (AxctlService.focusedMonitor && AxctlService.focusedMonitor.name) ? AxctlService.focusedMonitor.name : ""

    // The screen focus was on before the current one: the first choice when
    // the focused screen is covered.
    property string currentName: ""
    property string previousName: ""
    onFocusedNameChanged: {
        if (!root.focusedName || root.focusedName === root.currentName)
            return;
        root.previousName = root.currentName;
        root.currentName = root.focusedName;
    }

    readonly property var connectedNames: {
        const names = [];
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            names.push(screens[i].name);
        return names;
    }

    // Screens that can show a notification: registered by a panel and connected.
    readonly property var candidates: {
        const connected = root.connectedNames;
        return Object.keys(root.covered).filter(n => connected.indexOf(n) !== -1);
    }

    readonly property string target: {
        if (!RoadieSettings.notifyFollowFocus)
            return "";
        const names = root.candidates;
        if (names.length <= 1)
            return "";
        const focused = root.focusedName;
        if (!focused)
            return "";
        const focusedHasNotch = names.indexOf(focused) !== -1;
        if (focusedHasNotch && !root.covered[focused])
            return focused;
        const free = names.filter(n => n !== focused && !root.covered[n]);
        if (free.length === 0)
            return focusedHasNotch ? focused : "";
        if (free.indexOf(root.previousName) !== -1)
            return root.previousName;
        return free[0];
    }

    onTargetChanged: console.log("NotificationRouter: notifications on", root.target || "every screen")
}
