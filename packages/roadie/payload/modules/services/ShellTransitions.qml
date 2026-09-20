pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme
import qs.modules.globals
import qs.modules.services

// Ambxst Roadie (drpezzer.roadie): the staged shell enter and leave.
//
// `progress` is the one number the shell's chrome follows: 1 = in place,
// 0 = slid out past the screen edge. The frame's thickness and rounding, the
// bar, notch and dock offsets all multiply by it, the wallpaper curtain (theme
// background colour) covers the wallpaper while it is 0, and the reservation
// windows only reserve space while `reserve` is true, so the compositor's
// windows follow the frame out and back in.
//
// Entering: progress runs 0 -> 1 once the config is loaded and the first
// wallpaper image has decoded (boot and reload alike).
//
// Leaving: `leave()` runs it 1 -> 0 and fades the wallpaper to the background
// colour. Quickshell exits about ten milliseconds after the SIGTERM that
// `ambxst reload` sends and runs no QML teardown, so this has to happen
// BEFORE the reload is issued: `reload()` (the `reload` ui.run command, the
// `roadie` IPC target) leaves first and issues `ambxst reload` when
// the animation is done. The optional `ambxst` wrapper in the package's
// extras/ does the same for a raw `ambxst reload` typed anywhere.
//
// The veil: for a raw kill without that wrapper, a tiny detached Quickshell
// helper (veil/Veil.qml) connected over a local socket maps the last
// wallpaper and frame the instant the shell's socket closes and plays the
// leave animation on its own, then holds the background colour until the next
// shell reports in. It is idle and windowless while the shell runs.
Singleton {
    id: root

    readonly property string modId: "drpezzer.roadie"

    // ─── settings (Settings > Mods > Ambxst Roadie) ────────────────
    property bool enterAnimation: true
    property int enterDuration: 650
    property int leaveDuration: 900
    property bool veilEnabled: true
    // "stock" | "quiet" | "off", see the on-screen display section.
    property string osd: "quiet"
    // Boot: whether to lock (see the boot section). "auto" | "always" | "never"
    property string bootLock: "auto"

    function applyValues(values) {
        if (!values)
            return;
        if (["stock", "quiet", "off"].indexOf(values.osd) !== -1)
            root.osd = values.osd;
        if (values.enterAnimation !== undefined)
            root.enterAnimation = !!values.enterAnimation;
        if (values.veilEnabled !== undefined)
            root.veilEnabled = !!values.veilEnabled;
        if (["auto", "always", "never"].indexOf(values.bootLock) !== -1)
            root.bootLock = values.bootLock;
        const d = Number(values.enterDuration);
        if (!isNaN(d) && d >= 0)
            root.enterDuration = d;
        const l = Number(values.leaveDuration);
        if (!isNaN(l) && l >= 0)
            root.leaveDuration = l;
    }

    property bool settingsLoaded: false

    function loadSettings() {
        if (typeof ModsService === "undefined" || typeof ModsService.getSettings !== "function") {
            root.settingsLoaded = true;
            return;
        }
        ModsService.getSettings(root.modId, (settings, error) => {
            if (!error && settings)
                root.applyValues(settings.values);
            root.settingsLoaded = true;
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId !== root.modId)
                return;
            const values = {};
            values[key] = value;
            root.applyValues(values);
            root.scheduleSync();
        }
    }

    // ─── state ─────────────────────────────────────────────────────────
    property bool entered: false
    property bool leaving: false

    readonly property bool inPlace: root.entered || !root.enterAnimation

    // Three animated channels, staged from one timeline so the shell reads as
    // one deliberate movement rather than parts reacting to a restart:
    //
    //   leave (base L = leaveDuration)          enter (base E = enterDuration)
    //   chrome  0        .. 0.85 L  InOutCubic   curtain 0        .. 1.4 E   OutCubic
    //   frame   0.2 L    .. 1.2 L   InOutCubic   frame   0.2 E    .. 1.2 E   OutCubic
    //   curtain 0.1 L    .. 1.5 L   InOutSine    chrome  0.45 E   .. 1.45 E  OutCubic
    //
    // The bar, notch and dock go first on the way out and arrive last on the
    // way in; the frame follows them out and leads them in; the wallpaper is
    // the slowest, so it is still fading when the chrome has gone and already
    // back when the chrome arrives.

    // Frame thickness and rounding (ScreenFrameContent): 1 in place, 0 gone.
    property real progress: 0
    // Bar, notch and dock offsets: 1 in place, 0 past the screen edge.
    property real chromeProgress: 0
    // Opacity of the background-colour sheet over the wallpaper.
    property real curtain: root.enterAnimation ? 1 : 0

    // Per-run parameters, set imperatively BEFORE the targets change so the
    // Behaviors read the right values whatever the binding order.
    property int frameDelay: 0
    property int frameDur: 0
    property int frameEasing: Easing.OutCubic
    property int chromeDelay: 0
    property int chromeDur: 0
    property int chromeEasing: Easing.OutCubic
    property int curtainDelay: 0
    property int curtainDur: 0
    property int curtainEasing: Easing.OutCubic

    readonly property bool animate: Config.animDuration > 0

    Behavior on progress {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.frameDelay }
            NumberAnimation { duration: root.frameDur; easing.type: root.frameEasing }
        }
    }
    Behavior on chromeProgress {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.chromeDelay }
            NumberAnimation { duration: root.chromeDur; easing.type: root.chromeEasing }
        }
    }
    Behavior on curtain {
        enabled: root.animate
        SequentialAnimation {
            PauseAnimation { duration: root.curtainDelay }
            NumberAnimation { duration: root.curtainDur; easing.type: root.curtainEasing }
        }
    }

    // Reservation windows reserve space only while this is true, so the
    // compositor's windows expand as the frame leaves and shrink as it
    // arrives. Flipped in step with the frame channel.
    property bool reserve: false

    Timer {
        id: reserveTimer
        onTriggered: root.reserve = root.inPlace && !root.leaving
    }

    // Total time the leave takes on screen; what leave() reports.
    readonly property int leaveTotal: Math.round(root.leaveDuration * 1.5) + 60
    readonly property int enterTotal: Math.round(root.enterDuration * 1.45) + 60

    // ─── entering ──────────────────────────────────────────────────────
    property int wallpapersShown: 0

    // Called by Wallpaper.qml when a screen's image has decoded (static) or
    // its player has been started (video/gif).
    function wallpaperShown(screenName) {
        root.wallpapersShown += 1;
        root.maybeEnter();
    }

    // Keyed on the bar config (which sizes the frame and bar), not on
    // Config.initialLoadComplete: that one also waits for optional config
    // files and never comes true on an install where they are absent.
    readonly property bool configReady: Config.barReady && Config.themeReady
    // And on the compositor state: until monitors and clients have arrived
    // the notch and dock believe the workspace is empty and reveal
    // themselves, only to hide again a moment later.
    readonly property bool monitorsReady: AxctlService.focusedMonitor !== null && (AxctlService.monitors.values || []).length > 0
    readonly property bool clientsReady: (AxctlService.clients.values || []).length > 0
    // The window list usually lands a beat after the monitors; wait for it,
    // but not forever (an empty workspace is a legitimate state).
    property bool clientsGrace: false
    Timer {
        id: clientsGraceTimer
        interval: 400
        onTriggered: root.clientsGrace = true
    }
    onMonitorsReadyChanged: {
        if (root.monitorsReady)
            clientsGraceTimer.restart();
    }
    readonly property bool compositorReady: root.monitorsReady && (root.clientsReady || root.clientsGrace)
    readonly property bool ready: root.configReady && root.compositorReady && root.startKnown

    function maybeEnter() {
        if (root.entered)
            return;
        if (root.ready && root.wallpapersShown > 0)
            settleTimer.restart();
    }

    function enter() {
        if (root.entered)
            return;
        const E = root.enterDuration;
        root.curtainDelay = 0;
        root.curtainDur = Math.round(E * 1.4);
        root.curtainEasing = Easing.OutCubic;
        root.frameDelay = Math.round(E * 0.2);
        root.frameDur = E;
        root.frameEasing = Easing.OutCubic;
        root.chromeDelay = Math.round(E * 0.45);
        root.chromeDur = E;
        root.chromeEasing = Easing.OutCubic;
        // Boot with a lock ahead: the bar, notch and dock stay off screen
        // behind the lock and enter once it is gone.
        root.chromeHeld = root.willLock;
        root.entered = true;
        root.applyTargets();
        root.tuneWindows(root.frameDur, "shellTransitionsEnter");
        if (root.willLock) {
            lockTimer.interval = Math.max(1, root.animate ? root.frameDelay + root.frameDur + 80 : 1);
            lockTimer.restart();
        } else if (root.barHeld) {
            // No lock: the bar slides in where the chrome would have started.
            barReleaseTimer.interval = Math.max(1, root.animate ? root.chromeDelay : 1);
            barReleaseTimer.restart();
        }
        osdStartTimer.interval = root.enterTotal + root.osdStartGrace;
        osdStartTimer.restart();
        reserveTimer.interval = Math.max(1, root.animate ? root.frameDelay : 1);
        reserveTimer.restart();
        windowsRestoreTimer.interval = root.enterTotal + 100;
        windowsRestoreTimer.restart();
        root.sendReady();
    }

    function applyTargets() {
        const on = root.inPlace && !root.leaving;
        root.progress = on ? 1 : 0;
        root.chromeProgress = on && !root.chromeHeld ? 1 : 0;
        root.curtain = on ? 0 : 1;
    }

    // ─── boot ──────────────────────────────────────────────────────────
    // The first shell start of a session is a boot; every later one is a
    // reload. A marker in the runtime dir (cleared at logout) tells them
    // apart. At boot:
    //
    //   1. the sheet (background colour) stays until the shell is ready;
    //   2. the sheet lifts and the frame comes in -- with the bar held away
    //      and the notch and dock held off screen if a lock is coming;
    //   3. the shell locks (bootLock: "always"; or "auto" unless the session
    //      was logged in through a greeter -- sddm, gdm, lightdm, greetd, ly
    //      and friends, by the PAM service name logind records; the
    //      *-autologin variants do not count -- or an external locker such as
    //      hyprlock is already up);
    //   4. on unlock, the bar, notch and dock enter as usual.
    readonly property string sessionMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-roadie-session"
    // Read synchronously, so the very first frame already knows. The probe
    // below writes the marker for the next start.
    FileView {
        id: markerFile
        path: root.sessionMarker
        blockLoading: true
        printErrors: false
    }
    // waitForJob: `loaded` on its own is not synchronous (blockLoading only
    // makes text() wait), and for the first ~400 ms of EVERY start this read
    // true -- every reload began as a boot, with the bar held away and then
    // sliding in on its own, straight into the fullscreen detection.
    readonly property bool firstStart: {
        markerFile.waitForJob();
        return !markerFile.loaded;
    }
    property bool startKnown: false
    property string loginService: ""
    property bool externalLocker: false
    // Notch and dock offsets held at 0 (chromeHeld); the bar held "away" the
    // way it is on an unfocused screen -- slab collapsed, no space reserved
    // -- from the first frame of a boot (barHeld), so it arrives with its
    // usual slide-and-windows motion when released. On a boot the bar's
    // chrome offset is skipped (barChrome 1): the slide is its entrance.
    property bool chromeHeld: false
    property bool barHeld: root.firstStart
    readonly property real barChrome: root.firstStart ? 1 : root.chromeProgress
    property bool lockIssued: false
    Timer {
        id: barReleaseTimer
        onTriggered: root.barHeld = false
    }

    readonly property var greeterServices: ["sddm", "gdm", "gdm-password", "gdm-launch-environment", "lightdm", "greetd", "ly", "lemurs", "emptty", "cosmic-greeter", "tuigreet", "xdm", "lxdm", "slim"]
    readonly property bool loggedInThroughGreeter: root.greeterServices.indexOf(root.loginService) !== -1
    readonly property bool willLock: root.firstStart && !root.lockIssued && (root.bootLock === "always" || (root.bootLock === "auto" && !root.loggedInThroughGreeter && !root.externalLocker))

    Process {
        id: startProbe
        running: true
        command: ["sh", "-c", [
            'if [ -e "$1" ]; then echo again; else echo started > "$1"; echo first; fi',
            'sid="${XDG_SESSION_ID:-}"',
            'if [ -z "$sid" ]; then sid=$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -u)" \'$2==u && $6=="user" {print $1; exit}\'); fi',
            'svc=$(loginctl show-session "$sid" -p Service --value 2>/dev/null); echo "service=$svc"',
            'if pgrep -x "hyprlock|swaylock|gtklock|waylock|hyprlock-wrapped" >/dev/null 2>&1; then echo locker; else echo nolocker; fi'
        ].join("\n"), "_", root.sessionMarker]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").map(l => l.trim());
                if ((lines.indexOf("first") !== -1) !== root.firstStart)
                    console.warn("ShellTransitions: marker file and probe disagree on first start; trusting the marker");
                for (const l of lines) {
                    if (l.startsWith("service="))
                        root.loginService = l.substring(8);
                }
                root.externalLocker = lines.indexOf("locker") !== -1;
                root.startKnown = true;
                console.log("ShellTransitions: start =", root.firstStart ? "boot" : "reload", "login service =", root.loginService || "?", "external locker =", root.externalLocker, "will lock =", root.willLock, "(settings", root.settingsLoaded ? "loaded)" : "pending)");
            }
        }
    }


    Timer {
        id: lockTimer
        property int waited: 0
        onTriggered: {
            // The decision needs the settings; they normally land well before
            // this, but never lock on a default the user may have changed.
            if (!root.settingsLoaded && waited < 3000) {
                waited += 200;
                interval = 200;
                restart();
                return;
            }
            if (!root.willLock) {
                if (root.barHeld && root.entered)
                    root.barHeld = false;
                return;
            }
            root.lockIssued = true;
            GlobalStates.lockscreenVisible = true;
            // If no lock actually appears, do not leave the chrome stranded.
            lockCheckTimer.restart();
        }
    }
    Timer {
        id: lockCheckTimer
        interval: 1500
        onTriggered: {
            if (root.chromeHeld && !GlobalStates.lockscreenVisible)
                root.releaseChrome();
        }
    }
    Connections {
        target: GlobalStates
        function onLockscreenVisibleChanged() {
            if (!GlobalStates.lockscreenVisible && root.chromeHeld)
                root.releaseChrome();
        }
    }

    function releaseChrome() {
        if (!root.chromeHeld)
            return;
        const E = root.enterDuration;
        root.chromeDelay = 0;
        root.chromeDur = E;
        root.chromeEasing = Easing.OutCubic;
        root.chromeHeld = false;
        root.barHeld = false;
        root.applyTargets();
        osdStartTimer.interval = E + root.osdStartGrace;
        osdStartTimer.restart();
        root.scheduleSync();
    }

    // `roadie bootPreview`: forget that this session has started, so the
    // next start plays the boot sequence (lock and all), then reload.
    Process {
        id: markerClear
        running: false
        command: ["rm", "-f", root.sessionMarker]
    }

    onEnterAnimationChanged: {
        if (!root.entered && !root.leaving)
            root.applyTargets();
    }

    // One frame between "decoded" and "lift the curtain" so the image has
    // actually been drawn under it.
    Timer {
        id: settleTimer
        interval: 50
        onTriggered: root.enter()
    }

    // Config and compositor ready but no image has reported in (no wallpaper
    // configured, a video that failed to start, ...): enter anyway after a beat.
    Timer {
        id: noImageTimer
        interval: 1500
        onTriggered: root.enter()
    }

    // Nothing may ever leave the shell frozen off screen.
    Timer {
        id: hardFallback
        interval: 6000
        running: true
        onTriggered: root.enter()
    }

    onReadyChanged: {
        if (root.ready) {
            root.maybeEnter();
            noImageTimer.restart();
            if (!root.enterAnimation && root.willLock) {
                lockTimer.interval = 1;
                lockTimer.restart();
            }
        }
    }

    onProgressChanged: {
        if (root.progress >= 1)
            root.scheduleSync();
    }

    // ─── on-screen display ─────────────────────────────────────────────
    // Stock Ambxst shows the volume / microphone / brightness OSD whenever
    // the matching service reports a change, and the services also report
    // when they read their initial state after a start: the PipeWire sink
    // and source during the first second or so, and every monitor the moment
    // its first brightness read lands, which over DDC can be ten seconds in.
    // So the pop-up plays over (or long after) the entry, and on some setups
    // it stutters while the shell is still loading. The OSD's handlers ask
    // osdAllowed() before showing anything:
    //
    //   "stock"  as upstream
    //   "quiet"  swallow the initial reports: volume and mic while the start
    //            window is open (entry + a grace), brightness when the report
    //            is the one that turned its monitor ready (start, wake and
    //            hotplug re-reads alike); real changes always show
    //   "off"    never show it
    property bool osdStartWindow: true
    readonly property int osdStartGrace: 1500
    Timer {
        id: osdStartTimer
        onTriggered: root.osdStartWindow = false
    }

    // Monitors whose `ready` has just flipped on. Brightness emits the
    // initial read in the same call right after setting ready, so it is
    // still marked when the OSD asks; cleared once the event loop moves on,
    // after every screen's OSD has asked.
    property var osdInitReads: ({})
    property int osdSwallowed: 0
    // Monitors under watch (diagnostics; one per screen).
    readonly property int osdWatched: osdMonitorWatch.count

    Instantiator {
        id: osdMonitorWatch
        model: Brightness.monitors
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onReadyChanged() {
                if (!modelData.ready)
                    return;
                const name = modelData.screen ? modelData.screen.name : "";
                root.osdInitReads[name] = true;
                Qt.callLater(() => { delete root.osdInitReads[name]; });
            }
        }
    }

    function osdAllowed(kind: string, screenName: string): bool {
        if (root.osd === "off")
            return false;
        if (root.osd !== "quiet")
            return true;
        const swallow = kind === "brightness"
            ? !!root.osdInitReads[screenName || ""]
            : root.osdStartWindow;
        if (swallow)
            root.osdSwallowed += 1;
        return !swallow;
    }

    // ─── leaving ───────────────────────────────────────────────────────
    // Slide out and fade to the background colour. Returns the number of
    // milliseconds until that is done (0 if already leaving), so a caller can
    // issue the real reload once the screen is quiet.
    function leave(): int {
        if (root.leaving)
            return 0;
        const L = root.leaveDuration;
        // Gentle throughout: ease-in-out, nothing snaps away. The chrome
        // leads, the frame follows, the wallpaper is still fading when the
        // rest has gone.
        root.chromeDelay = 0;
        root.chromeDur = Math.round(L * 0.85);
        root.chromeEasing = Easing.InOutCubic;
        root.frameDelay = Math.round(L * 0.2);
        root.frameDur = L;
        root.frameEasing = Easing.InOutCubic;
        root.curtainDelay = Math.round(L * 0.1);
        root.curtainDur = Math.round(L * 1.4);
        root.curtainEasing = Easing.InOutSine;
        root.leaving = true;
        root.applyTargets();
        root.tuneWindows(root.frameDur, "shellTransitionsLeave");
        reserveTimer.interval = Math.max(1, root.animate ? root.frameDelay : 1);
        reserveTimer.restart();
        // The frame is done at frameDelay + frameDur; put the compositor's
        // window animation back before the reload kills us.
        windowsRestoreTimer.interval = root.frameDelay + root.frameDur + 60;
        windowsRestoreTimer.restart();
        root.send({ type: "leaving" });
        return root.animate ? root.leaveTotal : 0;
    }

    // Leave, then issue the real `ambxst reload`. The environment marker tells
    // the optional `ambxst` wrapper not to ask for another leave.
    function reload(): int {
        const ms = root.leave();
        reloadTimer.interval = Math.max(1, ms);
        reloadTimer.restart();
        return ms;
    }

    Timer {
        id: reloadTimer
        onTriggered: {
            Quickshell.execDetached({
                command: ["ambxst", "reload"],
                environment: ({ "AMBXST_SHELL_LEAVING": "1" })
            });
        }
    }

    IpcHandler {
        target: "roadie"

        function leave(): int {
            return root.leave();
        }

        function reload(): int {
            return root.reload();
        }

        function progress(): real {
            return root.progress;
        }

        // The farewell (ShellFarewell): `shutdown` / `reboot` do what the power
        // menu's buttons do, on the focused screen; `farewellPreview` plays the
        // same thing with a quote of that kind and then backs out, running
        // nothing; `farewellCancel` is the Escape key.
        function shutdown(): bool {
            return ShellFarewell.intercept("systemctl poweroff");
        }
        function reboot(): bool {
            return ShellFarewell.intercept("systemctl reboot");
        }
        function farewellPreview(kind: string): bool {
            const mon = AxctlService.focusedMonitor;
            return ShellFarewell.begin(kind === "reboot" ? "reboot" : "shutdown", "", mon && mon.name ? mon.name : "", true);
        }
        function farewellCancel(): void {
            ShellFarewell.cancel();
        }

        function bootPreview(): int {
            markerClear.running = true;
            return root.reload();
        }
        function bootState(): string {
            return JSON.stringify({ startKnown: root.startKnown, firstStart: root.firstStart, loginService: root.loginService, loggedInThroughGreeter: root.loggedInThroughGreeter, externalLocker: root.externalLocker, bootLock: root.bootLock, willLock: root.willLock, lockIssued: root.lockIssued, chromeHeld: root.chromeHeld, barHeld: root.barHeld, entered: root.entered, locked: GlobalStates.lockscreenVisible });
        }

        // The user's own quotes (the same file the editor under the mod's
        // settings writes): `farewellQuotes` prints them, `farewellAdd
        // shutdown|reboot "<line>" ["<from>"]` adds one, `farewellRemove
        // shutdown|reboot <index>` drops one, `farewellHide "<built-in line>"
        // true|false` switches a built-in line off or back on.
        function farewellQuotes(): string {
            return JSON.stringify(ShellFarewell.userDoc(), null, 2);
        }
        function farewellAdd(kind: string, text: string, source: string): bool {
            return ShellFarewell.addUserQuote(kind, text, source);
        }
        function farewellRemove(kind: string, index: int): void {
            ShellFarewell.removeUserQuote(kind, index);
        }
        function farewellHide(text: string, hidden: bool): void {
            ShellFarewell.setHidden(text, hidden);
        }
        function farewellState(): string {
            return JSON.stringify({ enabled: ShellFarewell.farewellEnabled, active: ShellFarewell.active, kind: ShellFarewell.kind, quote: ShellFarewell.quote, source: ShellFarewell.source, screen: ShellFarewell.screenName, expand: ShellFarewell.expand, solid: ShellFarewell.solid, text: ShellFarewell.text, holding: ShellFarewell.holding, committed: ShellFarewell.committed, dryRun: ShellFarewell.dryRun, holdMs: ShellFarewell.holdMs });
        }

        // Diagnostics: `qs ipc --pid $(cat $XDG_RUNTIME_DIR/ambxst-qs.pid) call roadie state`
        function state(): string {
            return JSON.stringify({
                entered: root.entered,
                leaving: root.leaving,
                progress: root.progress,
                chromeProgress: root.chromeProgress,
                curtain: root.curtain,
                reserve: root.reserve,
                compositorReady: root.compositorReady,
                wallpapersShown: root.wallpapersShown,
                configReady: root.configReady,
                initialLoadComplete: Config.initialLoadComplete,
                veilConnected: !!root.client,
                osd: root.osd,
                osdStartWindow: root.osdStartWindow,
                osdWatched: root.osdWatched,
                osdSwallowed: root.osdSwallowed,
                wallpapers: root.wallpapers.length,
                frames: root.frames.length
            });
        }
    }

    // ─── registry (filled by the patched Wallpaper / ScreenFrameContent) ──
    property var wallpapers: []
    property var frames: []

    function registerWallpaper(w) {
        if (!w || root.wallpapers.indexOf(w) !== -1)
            return;
        root.wallpapers = root.wallpapers.concat([w]);
        root.scheduleSync();
    }
    function unregisterWallpaper(w) {
        root.wallpapers = root.wallpapers.filter(x => x && x !== w);
        root.scheduleSync();
    }
    function registerFrame(f) {
        if (!f || root.frames.indexOf(f) !== -1)
            return;
        root.frames = root.frames.concat([f]);
        root.scheduleSync();
    }
    function unregisterFrame(f) {
        root.frames = root.frames.filter(x => x && x !== f);
        root.scheduleSync();
    }

    // Re-snapshot whenever something the veil draws changes.
    Instantiator {
        model: root.wallpapers
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onEffectiveWallpaperChanged() { root.scheduleSync(); }
            function onCurrentScreenNameChanged() { root.scheduleSync(); }
        }
    }

    Instantiator {
        model: root.frames
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onTopThicknessChanged() { root.scheduleSync(); }
            function onBottomThicknessChanged() { root.scheduleSync(); }
            function onLeftThicknessChanged() { root.scheduleSync(); }
            function onRightThicknessChanged() { root.scheduleSync(); }
            function onTargetInnerRadiusChanged() { root.scheduleSync(); }
            function onFrameEnabledChanged() { root.scheduleSync(); }
        }
    }

    Connections {
        target: Colors
        ignoreUnknownSignals: true
        function onBackgroundChanged() { root.scheduleSync(); }
    }

    Connections {
        target: Config.theme
        ignoreUnknownSignals: true
        function onSrBgChanged() { root.scheduleSync(); }
    }

    // ─── compositor window animation ───────────────────────────────────
    // The windows expanding into the frame's space (and shrinking back) are
    // moved by the compositor with its own resize animation, which on
    // Hyprland is `windowsMove` (250 ms by default): they snapped ahead of
    // the frame. For the duration of a transition that animation is retuned
    // to the frame channel's duration and easing, so windows and frame move
    // as one, then restored. Hyprland only; other compositors are left alone.
    readonly property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""
    readonly property string windowsStateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/roadie-windowsmove.json"

    // Effective original windowsMove settings, captured once at startup.
    property var windowsOriginal: null
    property bool windowsTuned: false

    function hypr(lua) {
        if (!root.hyprland)
            return;
        Quickshell.execDetached({ command: ["hyprctl", "eval", lua] });
    }

    function luaAnim(speed, bezier, style) {
        let lua = "hl.animation({ leaf = \"windowsMove\", enabled = true, speed = " + Number(speed).toFixed(2);
        if (bezier)
            lua += ", bezier = \"" + bezier + "\"";
        if (style)
            lua += ", style = \"" + style + "\"";
        return lua + " })";
    }

    function tuneWindows(durationMs, curve) {
        if (!root.hyprland || !root.animate || !root.windowsOriginal)
            return;
        if (!root.windowsTuned) {
            root.windowsTuned = true;
            // Remember the originals on disk so a shell killed mid-transition
            // (cold reload) still gets them restored by the next one.
            windowsStateWriter.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", root.windowsStateFile, JSON.stringify(root.windowsOriginal)];
            windowsStateWriter.running = true;
        }
        // Speed is in units of 100 ms. The curve is (re)registered in the
        // same call: Ambxst reloads the Hyprland config after every shell
        // start, which drops curves registered at runtime, and a missing
        // curve silently falls back to Hyprland's default (a fast start),
        // which is exactly the lurch this is meant to remove.
        root.hypr(root.curveLua(curve) + "; " + root.luaAnim(Math.max(0.1, durationMs / 100), curve, ""));
    }

    function restoreWindows(values) {
        const o = values || root.windowsOriginal;
        if (!root.hyprland || !o)
            return;
        root.hypr(root.luaAnim(o.speed, o.bezier, o.style));
        root.windowsTuned = false;
        windowsStateWriter.command = ["rm", "-f", root.windowsStateFile];
        windowsStateWriter.running = true;
    }

    Timer {
        id: windowsRestoreTimer
        onTriggered: root.restoreWindows(null)
    }

    Process {
        id: windowsStateWriter
        running: false
    }

    // Capture the effective windowsMove settings (walk up the tree if it is
    // not overridden itself), and restore a previous shell's leftovers.
    Process {
        id: windowsProbe
        running: false
        command: ["sh", "-c", "hyprctl animations -j; echo; echo ---STATE---; cat \"$1\" 2>/dev/null", "_", root.windowsStateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("---STATE---");
                let anims = null;
                try {
                    const d = JSON.parse(parts[0]);
                    anims = Array.isArray(d) ? d[0] : (d.animations || null);
                } catch (e) {}
                let leftover = null;
                if (parts.length > 1 && parts[1].trim().length > 0) {
                    try { leftover = JSON.parse(parts[1].trim()); } catch (e) {}
                }
                if (leftover && leftover.speed !== undefined) {
                    // A previous shell died mid-transition: these are the real
                    // originals, and Hyprland is still holding our tuning.
                    root.windowsOriginal = leftover;
                    root.restoreWindows(leftover);
                    return;
                }
                if (!Array.isArray(anims))
                    return;
                const byName = {};
                for (const a of anims)
                    byName[a.name] = a;
                let eff = null;
                for (const name of ["windowsMove", "windows", "global"]) {
                    const a = byName[name];
                    if (a && a.overridden && a.enabled) { eff = a; break; }
                }
                if (!eff) {
                    // Hyprland's built-in default when nothing is set.
                    eff = { speed: 10, bezier: "default", style: "" };
                }
                root.windowsOriginal = { speed: eff.speed, bezier: eff.bezier || "default", style: "" };
            }
        }
    }

    // The two easing curves the frame channel uses (ease-in-out cubic on the
    // way out, ease-out cubic on the way in), as Hyprland bezier definitions.
    function curveLua(name) {
        if (name === "shellTransitionsLeave")
            return "hl.curve(\"shellTransitionsLeave\", { type = \"bezier\", points = { {0.65, 0.0}, {0.35, 1.0} } })";
        return "hl.curve(\"shellTransitionsEnter\", { type = \"bezier\", points = { {0.33, 1.0}, {0.68, 1.0} } })";
    }

    // ─── veil protocol ─────────────────────────────────────────────────
    // Newline-delimited JSON, shell -> veil only:
    //   {"type":"state", ...snapshot()}   on connect and whenever it changes
    //   {"type":"leaving"}                the shell is fading out itself
    //   {"type":"staying"}                ...it is not after all (a farewell backed out)
    //   {"type":"ready"}                  this shell's wallpaper is on screen
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ambxst-veil.sock"
    readonly property string veilQml: Quickshell.shellPath("modules/services/veil/Veil.qml")

    property var client: null
    property int spawnsThisMinute: 0

    function frameColor() {
        const cfg = Config.theme.srBg;
        let c = Colors.background;
        let a = 1;
        if (cfg) {
            const stops = cfg.gradient;
            if (stops && stops.length > 0 && stops[0] && stops[0][0])
                c = Config.resolveColor(stops[0][0]);
            if (cfg.opacity !== undefined && cfg.opacity !== null)
                a = Number(cfg.opacity);
            if (isNaN(a))
                a = 1;
        }
        const col = Qt.color(c);
        return Qt.rgba(col.r, col.g, col.b, col.a * a).toString();
    }

    function snapshot() {
        const screens = {};
        for (const w of root.wallpapers) {
            if (!w || !w.currentScreenName)
                continue;
            let path = w.effectiveWallpaper || "";
            if (path && typeof w.getLockscreenFramePath === "function")
                path = w.getLockscreenFramePath(path) || path;
            screens[w.currentScreenName] = Object.assign(screens[w.currentScreenName] || {}, {
                name: w.currentScreenName,
                wall: path
            });
        }
        for (const f of root.frames) {
            if (!f || !f.targetScreen)
                continue;
            const name = f.targetScreen.name;
            screens[name] = Object.assign(screens[name] || { name: name, wall: "" }, {
                frame: {
                    enabled: !!f.frameEnabled,
                    t: f.topThickness,
                    b: f.bottomThickness,
                    l: f.leftThickness,
                    r: f.rightThickness,
                    radius: f.targetInnerRadius
                }
            });
        }
        return {
            type: "state",
            bg: Colors.background.toString(),
            frameColor: root.frameColor(),
            leave: root.leaveDuration,
            screens: Object.values(screens)
        };
    }

    Timer {
        id: syncTimer
        interval: 150
        onTriggered: root.sendState()
    }

    function scheduleSync() {
        if (root.client && root.progress >= 1)
            syncTimer.restart();
    }

    function send(obj) {
        if (!root.client || !root.client.connected)
            return;
        root.client.write(JSON.stringify(obj) + "\n");
        root.client.flush();
    }

    function sendState() {
        if (root.progress < 1 || root.leaving)
            return;
        root.send(root.snapshot());
    }

    function sendReady() {
        root.send({ type: "ready" });
    }

    SocketServer {
        id: server
        active: root.veilEnabled
        path: root.socketPath
        onActiveStatusChanged: {
            if (active)
                spawnTimer.restart();
        }
        handler: Socket {
            id: conn
            onConnectedChanged: {
                if (conn.connected) {
                    root.client = conn;
                    root.sendState();
                    if (root.entered)
                        root.sendReady();
                } else if (root.client === conn) {
                    root.client = null;
                    spawnTimer.restart();
                }
            }
            parser: SplitParser {
                onRead: msg => {}
            }
        }
    }

    // Spawn the helper when none is connected. Delayed so a helper that is
    // still shutting down (after serving the previous reload) has gone first.
    Timer {
        id: spawnTimer
        interval: 1000
        onTriggered: root.ensureVeil()
    }

    Timer {
        id: spawnBudget
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.spawnsThisMinute = 0
    }

    function ensureVeil() {
        if (!root.veilEnabled || root.client || root.leaving)
            return;
        if (root.spawnsThisMinute >= 5) {
            console.warn("ShellTransitions: veil helper keeps exiting, not respawning this minute");
            return;
        }
        root.spawnsThisMinute += 1;
        // setsid: the helper must not sit in Quickshell's process group, which
        // the Ambxst daemon kills as a whole on shutdown.
        Quickshell.execDetached({
            command: ["setsid", "-f", "qs", "-p", root.veilQml],
            workingDirectory: Quickshell.shellDir
        });
        // If it failed to come up, try again later (bounded above).
        retryTimer.restart();
    }

    Timer {
        id: retryTimer
        interval: 4000
        onTriggered: {
            if (!root.client)
                spawnTimer.restart();
        }
    }

    Component.onCompleted: {
        loadSettings();
        if (root.hyprland)
            windowsProbe.running = true;
        // This singleton is created on first use, which is usually after the
        // config has already finished loading, so the change signal above
        // never comes: evaluate the entry conditions once right now.
        if (root.monitorsReady)
            clientsGraceTimer.restart();
        if (root.ready) {
            root.maybeEnter();
            noImageTimer.restart();
        }
        // Same for the socket server: it was active before any handler could
        // observe the change, so arm the first spawn here.
        if (server.active)
            spawnTimer.restart();
    }
}
