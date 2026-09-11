pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import qs.modules.services

// Mod Updater: finds newer versions of installed mods and installs them.
//
// Checking never touches the mod manager; a bundled script asks each mod's
// source for its current manifest (local directory, git clone, or the raw
// GitHub manifest for tree URLs) and this service compares versions. Installing
// goes through ModsService.update, which is the same path as the Update button
// in a mod's details, so every install is a normal generation rebuild with the
// usual restart banner and rollback behind it.
Singleton {
    id: root

    readonly property string modId: "drpezzer.mod-updater"
    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/ambxst/mod_update_check.json"
    readonly property string scriptPath: Qt.resolvedUrl("mod_update_check.sh").toString().replace(/^file:\/\//, "")
    readonly property int modsSettingsTab: 10

    // Settings (mod settings schema, stored by the mod manager)
    property bool autoCheck: false
    property bool autoInstall: false
    property int checkIntervalHours: 6
    property bool settingsLoaded: false

    // Check state
    property bool checking: false
    property bool checkedOnce: false
    // True for a moment after a manual check finds nothing; the panel button
    // shows "No updates" while it is set, then returns to its idle label.
    property bool noUpdatesFlash: false
    property var updates: ({})
    readonly property int updateCount: Object.keys(root.updates).length
    property var checkErrors: ({})
    property string lastError: ""
    property double lastCheckTime: 0
    property double snoozeUntil: 0

    // Install state
    property bool installing: false
    property var installQueue: []
    property int installedCount: 0
    property string installingId: ""

    // ── settings ───────────────────────────────────────────────────────

    function applySettings(values) {
        if (!values)
            return;
        if (values.autoCheck !== undefined)
            root.autoCheck = !!values.autoCheck;
        if (values.autoInstall !== undefined)
            root.autoInstall = !!values.autoInstall;
        if (values.checkIntervalHours !== undefined) {
            const hours = Number(values.checkIntervalHours);
            if (!isNaN(hours) && hours >= 1)
                root.checkIntervalHours = Math.round(hours);
        }
        root.settingsLoaded = true;
    }

    function loadSettings() {
        ModsService.getSettings(root.modId, (settings, error) => {
            if (error) {
                console.warn("[ModUpdateService] settings unavailable:", error);
                return;
            }
            root.applySettings(settings?.values);
        });
    }

    function setSetting(key, value) {
        BackendService.call("mods.setSetting", { id: root.modId, key, value }, (result, error) => {
            if (error) {
                root.lastError = String(error);
                ModsService.errorMessage = String(error);
                return;
            }
            root.applySettings(result?.values);
            ModsService.statusMessageKey = "mods.status_setting_saved";
        });
    }

    function setAutoCheck(enabled) { root.setSetting("autoCheck", !!enabled); }
    function setAutoInstall(enabled) { root.setSetting("autoInstall", !!enabled); }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId !== root.modId)
                return;
            const values = {};
            values[key] = value;
            root.applySettings(values);
        }
        // A rebuilt status carries the installed versions; drop entries that
        // are now current so the buttons follow what the manager reports.
        function onModsChanged() {
            root.pruneUpdates();
        }
    }

    // ── cache ──────────────────────────────────────────────────────────

    FileView {
        id: cacheView
        path: root.cacheFile
        onLoaded: {
            try {
                const content = text();
                if (content && content.trim() !== "") {
                    const data = JSON.parse(content);
                    root.lastCheckTime = data.lastCheckTime || 0;
                    root.snoozeUntil = data.snoozeUntil || 0;
                }
            } catch (e) {
                console.log("[ModUpdateService] cache unreadable:", e);
            }
        }
    }

    function saveCache() {
        cacheView.setText(JSON.stringify({
            lastCheckTime: root.lastCheckTime,
            snoozeUntil: root.snoozeUntil
        }));
    }

    // ── checking ───────────────────────────────────────────────────────

    // "1.2.10" > "1.2.9"; strings that do not parse as dotted numbers count
    // as an update when they differ, so a tagged pre-release still shows up.
    function isNewer(latest, current) {
        if (!latest || latest === current)
            return false;
        const l = String(latest).split(".").map(Number);
        const c = String(current ?? "").split(".").map(Number);
        if (l.some(isNaN) || c.some(isNaN))
            return true;
        for (let i = 0; i < Math.max(l.length, c.length); i++) {
            const lv = l[i] || 0;
            const cv = c[i] || 0;
            if (lv > cv) return true;
            if (lv < cv) return false;
        }
        return false;
    }

    property bool _automaticCheck: false

    function checkForUpdates(automatic) {
        if (root.checking || root.installing)
            return;
        root._automaticCheck = !!automatic;
        root.checking = true;
        root.lastError = "";
        if (!automatic) {
            ModsService.errorMessage = "";
            ModsService.statusMessage = "";
            ModsService.statusMessageKey = "";
        }
        // Fresh status straight from the manager, without flipping
        // ModsService.busy under the panel's buttons.
        BackendService.call("mods.status", {}, (result, error) => {
            if (error) {
                root.finishCheck({}, {}, String(error));
                return;
            }
            const mods = result?.mods ?? [];
            const args = [];
            for (let i = 0; i < mods.length; i++) {
                const mod = mods[i];
                if (!mod?.id)
                    continue;
                args.push(mod.id + "\t" + (mod.sourceType ?? "") + "\t" + (mod.source ?? ""));
            }
            if (args.length === 0) {
                root.finishCheck({}, {}, "");
                return;
            }
            root._currentMods = mods;
            checkProcess.command = ["bash", root.scriptPath].concat(args);
            checkProcess.running = true;
        });
    }

    property var _currentMods: []

    Process {
        id: checkProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseCheckOutput(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[ModUpdateService] checker:", text.trim());
            }
        }
    }

    function parseCheckOutput(output) {
        const latest = {};
        const errors = {};
        const lines = String(output ?? "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const tab = line.indexOf("\t");
            if (tab <= 0)
                continue;
            const id = line.slice(0, tab);
            const value = line.slice(tab + 1).trim();
            if (value.startsWith("ERR:"))
                errors[id] = value.slice(4);
            else
                latest[id] = value;
        }
        const found = {};
        const mods = root._currentMods ?? [];
        for (let i = 0; i < mods.length; i++) {
            const mod = mods[i];
            const remote = latest[mod.id];
            if (remote && root.isNewer(remote, mod.version)) {
                found[mod.id] = {
                    id: mod.id,
                    name: mod.name ?? mod.id,
                    version: remote,
                    currentVersion: mod.version ?? "",
                    enabled: !!mod.enabled
                };
            }
        }
        root.finishCheck(found, errors, "");
    }

    function finishCheck(found, errors, error) {
        root.updates = found;
        root.checkErrors = errors;
        root.lastError = error;
        root.checking = false;
        root.checkedOnce = true;
        root.lastCheckTime = Date.now();
        root.saveCache();

        const count = Object.keys(found).length;
        if (error !== "") {
            if (!root._automaticCheck)
                ModsService.errorMessage = error;
            return;
        }
        if (!root._automaticCheck) {
            if (count === 0) {
                root.noUpdatesFlash = true;
                noUpdatesTimer.restart();
            }
            return;
        }
        if (count === 0)
            return;
        if (root.autoInstall) {
            root.updateAll(true);
            return;
        }
        if (Date.now() < root.snoozeUntil)
            return;
        root.notifyUpdatesAvailable(found);
    }

    // Entries whose installed version caught up with the remote one drop out.
    function pruneUpdates() {
        const mods = ModsService.mods ?? [];
        const current = {};
        for (let i = 0; i < mods.length; i++)
            current[mods[i].id] = mods[i].version ?? "";
        const kept = {};
        let changed = false;
        const ids = Object.keys(root.updates);
        for (let i = 0; i < ids.length; i++) {
            const entry = root.updates[ids[i]];
            if (current[ids[i]] !== undefined && !root.isNewer(entry.version, current[ids[i]])) {
                changed = true;
                continue;
            }
            if (current[ids[i]] === undefined) {
                changed = true;
                continue;
            }
            kept[ids[i]] = entry;
        }
        if (changed)
            root.updates = kept;
    }

    // ── installing ─────────────────────────────────────────────────────

    function updateOne(id) {
        if (root.installing || ModsService.busy)
            return;
        const entry = root.updates[id];
        if (!entry)
            return;
        root.installQueue = [id];
        root.startNextInstall(false);
    }

    function updateAll(automatic) {
        if (root.installing || ModsService.busy)
            return;
        root.installQueue = Object.keys(root.updates);
        if (root.installQueue.length === 0)
            return;
        root.installedCount = 0;
        root.startNextInstall(!!automatic);
    }

    property bool _automaticInstall: false

    function startNextInstall(automatic) {
        root._automaticInstall = automatic;
        if (root.installQueue.length === 0) {
            root.installing = false;
            root.installingId = "";
            if (automatic && root.installedCount > 0)
                root.notifyInstalled(root.installedCount);
            return;
        }
        root.installing = true;
        const queue = root.installQueue.slice();
        const id = queue.shift();
        root.installQueue = queue;
        root.installingId = id;
        const entry = root.updates[id];
        ModsService.update(id, entry ? entry.enabled : false);
    }

    Connections {
        target: ModsService
        function onBusyChanged() {
            if (ModsService.busy || !root.installing)
                return;
            // ModsService clears busy before it records the error for a failed
            // request, so judge the outcome one tick later.
            Qt.callLater(root.afterInstallStep);
        }
    }

    function afterInstallStep() {
        if (!root.installing || ModsService.busy)
            return;
        if (ModsService.errorMessage !== "") {
            // Stop the queue on the first failure; the panel shows the error.
            root.installQueue = [];
            root.installing = false;
            root.installingId = "";
            return;
        }
        root.installedCount += 1;
        root.startNextInstall(root._automaticInstall);
    }

    // ── notifications ──────────────────────────────────────────────────

    function openModsPanel() {
        if (!GlobalStates.settingsWindowVisible)
            GlobalShortcuts.toggleSettings();
        GlobalStates.settingsCurrentTab = root.modsSettingsTab;
    }

    function notifyUpdatesAvailable(found) {
        const ids = Object.keys(found);
        const names = ids.map(id => found[id].name + " " + found[id].version);
        const summary = ids.length === 1 ? "Mod update available" : ids.length + " mod updates available";
        Notifications.notifyInternal({
            summary: summary,
            body: names.join(", "),
            appName: "Ambxst Mods",
            appIcon: "system-software-update",
            urgency: "normal",
            replaceKey: "ambxst-mod-updates",
            actions: [
                { identifier: "open",   text: "Open Mods" },
                { identifier: "later",  text: "Later" },
                { identifier: "update", text: "Update all" }
            ],
            actionHandlers: {
                "open": function () { root.openModsPanel(); },
                "later": function () {
                    root.snoozeUntil = Date.now() + 8 * 3600000;
                    root.saveCache();
                },
                "update": function () { root.updateAll(true); }
            }
        });
    }

    function notifyInstalled(count) {
        Notifications.notifyInternal({
            summary: count === 1 ? "1 mod updated" : count + " mods updated",
            body: "Restart Ambxst to load the new versions.",
            appName: "Ambxst Mods",
            appIcon: "system-software-update",
            urgency: "normal",
            replaceKey: "ambxst-mod-updates",
            actions: [
                { identifier: "open",    text: "Open Mods" },
                { identifier: "restart", text: "Restart now" }
            ],
            actionHandlers: {
                "open": function () { root.openModsPanel(); },
                "restart": function () { ModsService.restart(); }
            }
        });
    }

    Timer {
        id: noUpdatesTimer
        interval: 2500
        onTriggered: root.noUpdatesFlash = false
    }

    // ── scheduling ─────────────────────────────────────────────────────

    // Boot check: wait for the manager socket and let the shell settle first.
    Timer {
        id: startupDelay
        interval: 90000
        running: true
        onTriggered: {
            if (root.autoCheck)
                root.checkForUpdates(true);
            periodic.running = true;
        }
    }

    Timer {
        id: periodic
        interval: 300000
        repeat: true
        onTriggered: {
            if (!root.autoCheck || root.checking || root.installing)
                return;
            if (Date.now() - root.lastCheckTime >= root.checkIntervalHours * 3600000)
                root.checkForUpdates(true);
        }
    }

    Component.onCompleted: root.loadSettings()
}
