pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import qs.modules.services

// Ambxst Roadie (drpezzer.roadie): finds newer versions of installed mods,
// says which of them need a newer Ambxst BEFORE anything is installed, and
// installs them. (Until Roadie 1.4.0 this was the separate Mod Updater mod.)
//
// Checking never touches the mod manager; a bundled script asks each mod's
// source for its current manifest (local directory, git clone, or the raw
// GitHub manifest for tree URLs) and this service compares versions. Installing
// goes through ModsService.update, which is the same path as the Update button
// in a mod's details, so every install is a normal generation rebuild with the
// usual restart banner and rollback behind it.
//
// An update whose manifest asks for an Ambxst the installed one does not match
// is BLOCKED: the manager would refuse it (and say so only after the click),
// and updating Ambxst first instead rebuilds the mods that are installed, where
// one that no longer applies leaves the shell without any mods. Blocked updates
// are never installed from here on their own. They are offered together with
// the Ambxst update, which roadie_update.sh runs in a terminal in the order
// that works: set the mods aside and fetch their new versions, update Ambxst,
// enable them again, restart once.
Singleton {
    id: root

    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/ambxst/mod_update_check.json"
    readonly property string scriptPath: Qt.resolvedUrl("mod_update_check.sh").toString().replace(/^file:\/\//, "")
    readonly property string updateScriptPath: Qt.resolvedUrl("roadie_update.sh").toString().replace(/^file:\/\//, "")
    readonly property int modsSettingsTab: 10

    // Settings (Settings > Roadie, ~/.config/ambxst/roadie.json)
    readonly property bool autoCheck: RoadieSettings.modAutoCheck
    readonly property bool autoInstall: RoadieSettings.modAutoInstall
    readonly property int checkIntervalHours: RoadieSettings.modCheckHours
    readonly property bool settingsLoaded: true

    function setAutoCheck(enabled) { RoadieSettings.set("modAutoCheck", !!enabled); }
    function setAutoInstall(enabled) { RoadieSettings.set("modAutoInstall", !!enabled); }

    // Check state
    property bool checking: false
    property bool checkedOnce: false
    // True for a moment after a manual check finds nothing; the panel button
    // shows "No updates" while it is set, then returns to its idle label.
    property bool noUpdatesFlash: false
    // Every newer version found, by mod id:
    //   { id, name, version, currentVersion, enabled,
    //     requires: "<ambxst range of the new version>",
    //     blocked:  the installed Ambxst does not match it,
    //     needs:    the Ambxst version that would ("" if a newer one would not help) }
    property var updates: ({})
    property var checkErrors: ({})
    property string lastError: ""
    property double lastCheckTime: 0
    property double snoozeUntil: 0

    // The Ambxst the last check ran against, and the one an update would bring
    // ("" when it could not be read).
    property string ambxstVersion: ""
    property string ambxstAvailable: ""

    readonly property var installableIds: Object.keys(root.updates).filter(id => !root.updates[id].blocked)
    readonly property var blockedIds: Object.keys(root.updates).filter(id => root.updates[id].blocked && root.updates[id].needs !== "")
    // What the panel's "Install N updates" counts: what can be installed now.
    readonly property int updateCount: root.installableIds.length
    readonly property int blockedCount: root.blockedIds.length
    // The lowest Ambxst that satisfies every blocked update.
    readonly property string ambxstNeeded: {
        let highest = "";
        for (let i = 0; i < root.blockedIds.length; i++) {
            const needs = root.updates[root.blockedIds[i]].needs;
            if (highest === "" || root.compareVersions(needs, highest) > 0)
                highest = needs;
        }
        return highest;
    }
    // Is that Ambxst out? Unknown counts as yes: the update script looks
    // again before it changes anything.
    readonly property bool ambxstReady: root.blockedCount > 0
        && (root.ambxstAvailable === "" || root.compareVersions(root.ambxstAvailable, root.ambxstNeeded) >= 0)

    // Install state
    property bool installing: false
    property var installQueue: []
    property int installedCount: 0
    property string installingId: ""

    Connections {
        target: ModsService
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
        printErrors: false
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

    // ── versions ───────────────────────────────────────────────────────

    // [major, minor, patch] or null; a "-suffix" is ignored, as the manager does.
    function parseVersion(raw) {
        const base = String(raw ?? "").trim().split("-")[0];
        const parts = base.split(".");
        if (parts.length !== 3)
            return null;
        const out = [];
        for (let i = 0; i < 3; i++) {
            if (!/^[0-9]+$/.test(parts[i]))
                return null;
            out.push(parseInt(parts[i], 10));
        }
        return out;
    }

    // -1, 0, 1; versions that do not parse compare equal.
    function compareVersions(a, b) {
        const x = root.parseVersion(a);
        const y = root.parseVersion(b);
        if (!x || !y)
            return 0;
        for (let i = 0; i < 3; i++) {
            if (x[i] < y[i]) return -1;
            if (x[i] > y[i]) return 1;
        }
        return 0;
    }

    function rangeTerms(constraint) {
        const terms = [];
        const fields = String(constraint ?? "").trim().split(/\s+/).filter(t => t !== "");
        for (let i = 0; i < fields.length; i++) {
            let op = "=";
            let value = fields[i];
            const ops = [">=", "<=", ">", "<", "="];
            for (let j = 0; j < ops.length; j++) {
                if (value.startsWith(ops[j])) {
                    op = ops[j];
                    value = value.slice(ops[j].length);
                    break;
                }
            }
            terms.push({ op: op, value: value });
        }
        return terms;
    }

    // The mod manager's own rule (backend/pkg/mods/version.go): every term of
    // the space-separated range must hold; an empty range matches anything.
    function matchesRange(version, constraint) {
        const terms = root.rangeTerms(constraint);
        if (terms.length === 0)
            return true;
        if (!root.parseVersion(version))
            return false;
        for (let i = 0; i < terms.length; i++) {
            if (!root.parseVersion(terms[i].value))
                return false;
            const cmp = root.compareVersions(version, terms[i].value);
            const op = terms[i].op;
            const ok = op === ">=" ? cmp >= 0 : op === "<=" ? cmp <= 0 : op === ">" ? cmp > 0 : op === "<" ? cmp < 0 : cmp === 0;
            if (!ok)
                return false;
        }
        return true;
    }

    // The Ambxst version a range starts at, if `version` lies below it: what
    // to tell the user to update to. "" when a newer Ambxst would not help
    // (the range ends below the installed one, or does not parse).
    function neededVersion(version, constraint) {
        const terms = root.rangeTerms(constraint);
        let lowest = "";
        for (let i = 0; i < terms.length; i++) {
            const op = terms[i].op;
            if (op !== ">=" && op !== ">" && op !== "=")
                continue;
            if (!root.parseVersion(terms[i].value))
                return "";
            if (lowest === "" || root.compareVersions(terms[i].value, lowest) > 0)
                lowest = terms[i].value;
        }
        if (lowest === "" || root.compareVersions(version, lowest) >= 0)
            return "";
        // Would that version satisfy the rest of the range?
        return root.matchesRange(lowest, terms.filter(t => t.op !== ">").map(t => t.op + t.value).join(" ")) ? lowest : "";
    }

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

    // ── checking ───────────────────────────────────────────────────────

    property bool _automaticCheck: false
    property var _currentMods: []
    property bool _bypass: false

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
            root.ambxstVersion = String(result?.baseVersion ?? "");
            root._bypass = !!result?.bypassVersionCheck;
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
        const ranges = {};
        const errors = {};
        let available = "";
        const lines = String(output ?? "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t");
            if (fields.length < 2 || fields[0] === "")
                continue;
            const id = fields[0];
            const value = fields[1].trim();
            if (id === "@ambxst") {
                available = value;
            } else if (value.startsWith("ERR:")) {
                errors[id] = value.slice(4);
            } else {
                latest[id] = value;
                ranges[id] = (fields[2] ?? "").trim();
            }
        }
        root.ambxstAvailable = available;
        const found = {};
        const mods = root._currentMods ?? [];
        for (let i = 0; i < mods.length; i++) {
            const mod = mods[i];
            const remote = latest[mod.id];
            if (!remote || !root.isNewer(remote, mod.version))
                continue;
            const range = ranges[mod.id] ?? "";
            // With the manager's version check bypassed nothing is refused,
            // so nothing is held back here either.
            const blocked = !root._bypass && root.ambxstVersion !== "" && !root.matchesRange(root.ambxstVersion, range);
            found[mod.id] = {
                id: mod.id,
                name: mod.name ?? mod.id,
                version: remote,
                currentVersion: mod.version ?? "",
                enabled: !!mod.enabled,
                requires: range,
                blocked: blocked,
                needs: blocked ? root.neededVersion(root.ambxstVersion, range) : ""
            };
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
        if (root.autoInstall && root.updateCount > 0) {
            // What needs a newer Ambxst waits; notifyInstalled mentions it.
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
        if (!entry || entry.blocked)
            return;
        root.installQueue = [id];
        root.startNextInstall(false);
    }

    function updateAll(automatic) {
        if (root.installing || ModsService.busy)
            return;
        root.installQueue = root.installableIds.slice();
        if (root.installQueue.length === 0)
            return;
        root.installedCount = 0;
        root.startNextInstall(!!automatic);
    }

    // Ambxst and the updates that wait for it, in a terminal (the installer
    // asks for a password). The script states what it will do and asks first.
    function updateWithAmbxst() {
        if (root.blockedCount === 0 || root.installing || ModsService.busy)
            return;
        const quote = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
        let command = "bash " + quote(root.updateScriptPath)
            + " --stage " + quote(root.blockedIds.join(","))
            + " --need " + quote(root.ambxstNeeded);
        if (root.installableIds.length > 0)
            command += " --then " + quote(root.installableIds.join(","));
        TerminalService.execDetached(command);
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

    // "needs Ambxst 1.3.9", and whether that is out yet.
    function ambxstLine() {
        if (root.blockedCount === 0)
            return "";
        const which = root.blockedCount === 1 ? "1 needs" : root.blockedCount + " need";
        const line = which + " Ambxst " + root.ambxstNeeded;
        if (!root.ambxstReady)
            return line + ", which is not out yet.";
        return line + ". Update Ambxst together with " + (root.blockedCount === 1 ? "it" : "them") + ", not before.";
    }

    function notifyUpdatesAvailable(found) {
        const ids = Object.keys(found);
        const names = ids.map(id => found[id].name + " " + found[id].version);
        const summary = ids.length === 1 ? "Mod update available" : ids.length + " mod updates available";
        const actions = [{ identifier: "open", text: "Open Mods" }, { identifier: "later", text: "Later" }];
        if (root.updateCount > 0)
            actions.push({ identifier: "update", text: root.blockedCount > 0 ? "Update " + root.updateCount : "Update all" });
        if (root.blockedCount > 0 && root.ambxstReady)
            actions.push({ identifier: "ambxst", text: "Update Ambxst too" });
        const extra = root.ambxstLine();
        Notifications.notifyInternal({
            summary: summary,
            body: names.join(", ") + (extra !== "" ? "\n" + extra : ""),
            appName: "Ambxst Mods",
            appIcon: "system-software-update",
            urgency: "normal",
            replaceKey: "ambxst-mod-updates",
            actions: actions,
            actionHandlers: {
                "open": function () { root.openModsPanel(); },
                "later": function () {
                    root.snoozeUntil = Date.now() + 8 * 3600000;
                    root.saveCache();
                },
                "update": function () { root.updateAll(true); },
                "ambxst": function () { root.updateWithAmbxst(); }
            }
        });
    }

    function notifyInstalled(count) {
        const extra = root.ambxstLine();
        const actions = [{ identifier: "open", text: "Open Mods" }, { identifier: "restart", text: "Restart now" }];
        if (root.blockedCount > 0 && root.ambxstReady)
            actions.push({ identifier: "ambxst", text: "Update Ambxst too" });
        Notifications.notifyInternal({
            summary: count === 1 ? "1 mod updated" : count + " mods updated",
            body: "Restart Ambxst to load the new versions." + (extra !== "" ? "\nStill waiting: " + extra : ""),
            appName: "Ambxst Mods",
            appIcon: "system-software-update",
            urgency: "normal",
            replaceKey: "ambxst-mod-updates",
            actions: actions,
            actionHandlers: {
                "open": function () { root.openModsPanel(); },
                "restart": function () { ModsService.restart(); },
                "ambxst": function () { root.updateWithAmbxst(); }
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

    // For tests and reports: `roadie updateState`.
    function report() {
        return {
            ambxst: root.ambxstVersion,
            ambxstAvailable: root.ambxstAvailable,
            ambxstNeeded: root.ambxstNeeded,
            ambxstReady: root.ambxstReady,
            autoCheck: root.autoCheck,
            autoInstall: root.autoInstall,
            checkIntervalHours: root.checkIntervalHours,
            checking: root.checking,
            installable: root.installableIds,
            blocked: root.blockedIds,
            updates: root.updates,
            errors: root.checkErrors
        };
    }
}
