pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

// mpris-player-fixes: state and actions for the "Patch browser" button on the
// mod's row in Settings > Mods. All the work is in mpris_browser_patch.py next
// to this file; this only runs it and mirrors its answers into properties.
Singleton {
    id: root

    readonly property string scriptPath: Qt.resolvedUrl("mpris_browser_patch.py").toString().replace(/^file:\/\//, "")

    property bool checked: false        // a status run has completed at least once
    property bool checking: false
    property bool patching: false
    property bool browserFound: false
    property bool patched: false
    property var browsers: []
    property string step: ""            // last progress step while patching
    property string stepBrowser: ""
    property string lastError: ""
    property double lastCheck: 0

    function refresh(force) {
        if (root.checking || root.patching) return;
        if (!force && root.checked && Date.now() - root.lastCheck < 15000) return;
        root.checking = true;
        statusProcess.command = ["python3", root.scriptPath, "status"];
        statusProcess.running = true;
    }

    function applyStatus(text) {
        root.lastCheck = Date.now();
        try {
            const s = JSON.parse(text);
            root.browsers = s.browsers || [];
            root.browserFound = !!s.browserFound;
            root.patched = !!s.patched;
            root.lastError = "";
        } catch (e) {
            root.lastError = "status: " + e;
        }
        root.checked = true;
    }

    function patch() {
        if (root.patching) return;
        root.patching = true;
        root.step = "";
        root.stepBrowser = "";
        root.lastError = "";
        patchProcess.command = ["python3", root.scriptPath, "patch"];
        patchProcess.running = true;
    }

    function onProgress(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        root.step = ev.step || "";
        root.stepBrowser = ev.browser || "";
        if (ev.step === "violentmonkey") {
            root.notify("Install Violentmonkey in " + ev.browser,
                        "The add-on page is open in " + ev.browser + ". Press \"Add to " + ev.browser.split(" ")[0] + "\" and confirm; the userscript comes next.");
        } else if (ev.step === "userscript") {
            root.notify("Install the MPRIS userscript in " + ev.browser,
                        "Violentmonkey is showing the script in " + ev.browser + ". Press \"Confirm installation\".");
        } else if (ev.step === "timeout") {
            root.notify("Browser patch not finished",
                        "Nothing was installed in " + ev.browser + " within five minutes. Press Patch browser again to retry.");
        } else if (ev.step === "no-browser") {
            root.notify("No supported browser found",
                        "Looked for Zen, Firefox, LibreWolf, Floorp and Waterfox profiles (native, Flatpak and Snap).");
        } else if (ev.step === "done") {
            root.applyStatus(line);
            if (root.patched) root.notify("Browser patched", "Playback position now reaches the MPRIS player. Reload the page that is playing.");
        }
    }

    function notify(summary, body) {
        if (typeof Notifications === "undefined" || typeof Notifications.notifyInternal !== "function") return;
        Notifications.notifyInternal({
            summary: summary,
            body: body,
            appName: "Ambxst Mods",
            appIcon: "web-browser",
            urgency: "normal",
            replaceKey: "ambxst-mpris-browser-patch"
        });
    }

    Process {
        id: statusProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[MprisBrowserPatchService] status:", text.trim());
            }
        }
        onExited: root.checking = false
    }

    Process {
        id: patchProcess
        running: false
        stdout: SplitParser {
            onRead: data => root.onProgress(data)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    root.lastError = text.trim();
                    console.warn("[MprisBrowserPatchService] patch:", text.trim());
                }
            }
        }
        onExited: {
            root.patching = false;
            root.refresh(true);
        }
    }

    // First look a few seconds after the shell is up; the panel refreshes
    // again whenever the row is shown.
    Timer {
        id: firstCheck
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.refresh(true)
    }
}
