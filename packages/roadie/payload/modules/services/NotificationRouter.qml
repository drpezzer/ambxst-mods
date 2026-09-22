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
// An empty target means "every screen", which is also the answer whenever the
// focused screen is unknown, so nothing is ever lost to a gap in the data.
// Each UnifiedShellPanel reports whether its screen is covered.
Singleton {
    id: root

    // Screen name -> true while a fullscreen window covers it.
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

    function forget(name) {
        if (!name || !(name in root.covered))
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

    readonly property var screenNames: {
        const names = [];
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            names.push(screens[i].name);
        return names;
    }

    readonly property string target: {
        if (!RoadieSettings.notifyFollowFocus)
            return "";
        const names = root.screenNames;
        if (names.length <= 1)
            return "";
        const focused = root.focusedName;
        if (!focused || names.indexOf(focused) === -1)
            return "";
        if (!root.covered[focused])
            return focused;
        const free = names.filter(n => n !== focused && !root.covered[n]);
        if (free.length === 0)
            return focused;
        if (free.indexOf(root.previousName) !== -1)
            return root.previousName;
        return free[0];
    }

    onTargetChanged: console.log("NotificationRouter: notifications on", root.target || "every screen")
}
