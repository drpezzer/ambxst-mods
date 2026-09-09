pragma Singleton

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

/**
 * Steamdeck Mode.
 *
 * Brings up Apollo + MoonDeck Buddy + Steam, hands the Deck a dedicated virtual
 * output, blanks the physical monitors and puts a password screen over them.
 * All the system-level work lives in scripts/steamdeck_mode.sh; this drives the
 * sequencing, the grace period and the re-lock timer.
 *
 * --- Why the state is persisted ---------------------------------------------
 *
 * A crash or a reload while Harrison is away must not drop the lock and leave
 * the desktop open, so the mode's flags are written to disk and a starting
 * shell restores straight back into a locked mode rather than a bare desktop.
 *
 * They go to a file of our own rather than through StateService. StateService
 * writes Quickshell.statePath("states.json"), and on this machine that file has
 * not been written since August - there are two `by-shell/<hash>` directories
 * and the live shell's one is empty, so every set() lands somewhere nothing
 * reads back. Relying on it meant the restored mode came back with active=false
 * and no lock. This file is written with an explicit mkdir -p and can be read
 * from a shell, which also makes it debuggable from a TTY.
 *
 * --- Why Caffeine is forced on ----------------------------------------------
 *
 * Harrison's idle chain (config/system.json) dims at 150s, locks at 300s, runs
 * `ambxst screen off` at 330s and SUSPENDS at 1800s. Two of those are fatal to
 * remote play: the screen-off hits every monitor through axctl including the
 * virtual one the Deck is streaming, and the suspend kills the session outright.
 * IdleService's master IdleMonitor is `respectInhibitors: true`, so holding
 * Caffeine suppresses that whole chain for as long as the mode is on.
 */
Singleton {
    id: root

    // Persisted: the mode itself, and whether it should currently be showing
    // the lock. `armed` is false only during the grace period and during the
    // 5 minute window after Harrison types his password.
    property bool active: false
    property bool armed: false

    // Grace period before the desk goes dark, so a misclick is harmless.
    // Pressing the button again during the countdown cancels the whole thing.
    property int graceSeconds: 15
    property int graceLeft: 0
    readonly property bool arming: graceLeft > 0

    // How long the desktop stays usable after a successful password before it
    // re-locks itself. Idle, not absolute: a quick task should not be cut off
    // mid-keystroke.
    property int relockSeconds: 300

    property string gameName: ""
    readonly property bool streaming: gameName !== ""

    // Caffeine's state before the mode took it over, so turning the mode off
    // restores what Harrison actually had rather than forcing it off.
    property bool caffeineWasOn: false

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/ambxst-steamdeck"
    readonly property string stateFile: stateDir + "/state.json"

    // --- Topaz -------------------------------------------------------------
    //
    // A Starlight render holds ~12 GB of VRAM (it is launched with
    // --max-gpu-mem 11), which is exactly what NVENC needs for a good stream.
    // So the queue is paused on the way in and resumed on the way out.
    //
    // Only ever resumed if WE paused it: if the queue was already paused by
    // hand, or there was no queue at all, the mode must leave it alone.
    // Persisted for the same reason `active` is - the entry sequence restarts
    // the shell, and a forgotten flag would either strand the queue paused or
    // resume something Harrison had paused deliberately.
    readonly property string topazCtl: Quickshell.env("HOME") + "/.local/bin/topaz-starlight-ctl"
    readonly property string topazStateFile: Quickshell.env("HOME") + "/.local/state/topaz-starlight/state"
    property bool topazPausedByUs: false

    readonly property string script: Qt.resolvedUrl("../../scripts/steamdeck_mode.sh").toString().replace("file://", "")
    readonly property string gameScript: Qt.resolvedUrl("../../scripts/steamdeck_game.sh").toString().replace("file://", "")

    signal failed(string reason)

    // --- entry / exit -------------------------------------------------------

    function toggle(): void {
        if (root.active)
            disable();
        else
            enable();
    }

    function enable(): void {
        if (root.active)
            return;

        root.caffeineWasOn = CaffeineService.inhibit;
        CaffeineService.inhibit = true;

        root.active = true;
        root.armed = false;
        persist();

        // Read the queue state, then pause it if it was running. Async, so it
        // lands a moment after the rest of entry - harmless, since the grace
        // period is 15s and nothing is streaming yet.
        topazStateProc.running = true;

        // Services and the virtual output come up immediately - none of it is
        // disruptive, and having Apollo warm makes the Deck's first connection
        // fast. Only the blanking waits for the grace period.
        up.running = true;
        root.graceLeft = root.graceSeconds;
        graceTimer.start();
    }

    // Cancel during the grace period: nothing has gone dark yet, so this is a
    // plain teardown with no lock involved.
    function cancel(): void {
        graceTimer.stop();
        root.graceLeft = 0;
        disable();
    }

    function disable(): void {
        graceTimer.stop();
        root.graceLeft = 0;

        root.active = false;
        root.armed = false;
        persist();

        CaffeineService.inhibit = root.caffeineWasOn;

        focusDesk.running = true;
        down.running = true;

        // Don't hand the GPU back to Topaz until the game has actually exited -
        // a stream torn down from the Deck can leave the title running for a
        // few seconds, and restarting a 12 GB render underneath it would fight
        // for VRAM with whatever is still on screen.
        if (root.topazPausedByUs)
            topazResumeWatch.start();
    }

    // Polls for "no Steam game running" and resumes the render queue once that
    // holds. Gives up after 2 minutes and resumes anyway, so a wedged game
    // process cannot strand the queue paused indefinitely.
    property int topazWaited: 0

    property Timer topazResumeWatch: Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.topazWaited += interval;
            gameCheckProc.running = true;
            if (root.topazWaited >= 120000) {
                stop();
                root.topazWaited = 0;
                root.resumeTopaz();
            }
        }
        onRunningChanged: {
            if (running)
                root.topazWaited = 0;
        }
    }

    property Process gameCheckProc: Process {
        command: ["sh", root.gameScript]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    return; // still playing
                topazResumeWatch.stop();
                root.topazWaited = 0;
                root.resumeTopaz();
            }
        }
    }

    function resumeTopaz(): void {
        if (!root.topazPausedByUs)
            return;
        root.topazPausedByUs = false;
        persist();
        Quickshell.execDetached([root.topazCtl, "resume"]);
    }

    property Process topazStateProc: Process {
        command: ["cat", root.topazStateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                // "" means no queue at all; "paused" means Harrison already
                // stopped it. Neither is ours to touch.
                if (text.trim() !== "running")
                    return;
                root.topazPausedByUs = true;
                root.persist();
                Quickshell.execDetached([root.topazCtl, "pause"]);
            }
        }
        stderr: StdioCollector {}
    }

    // --- the blanking handoff -----------------------------------------------
    //
    // Blank and lock in this same shell instance. An earlier version restarted
    // the shell here, because Ambxst mis-reserves its bar area after a monitor
    // change and a restart is the known fix for that. It was the wrong moment:
    // the restart tore down the lock surface a few seconds after the screens
    // went dark, leaving a blanked desk with no lock and nothing listening for
    // input to wake it - unrecoverable without a TTY.
    //
    // The reservation fix is now deferred to the first unlock (see unlock()),
    // which is both the first time the bar is actually looked at and a moment
    // when the desktop is meant to be appearing anyway.
    function armAndBlank(): void {
        root.armed = true;
        persist();
        applyArmedState();
    }

    // Called on startup when a restored state says we should be dark.
    function applyArmedState(): void {
        // Show the lock before letting it fade, rather than cutting straight to
        // black. It confirms the mode actually engaged, gives a last chance to
        // notice a mistaken entry, and means the desk is never dark without
        // having proven it can light up again. reblankTimer takes it to black
        // 30s later.
        root.displaysAwake = true;
        reblankTimer.restart();
        if (root.useDpms)
            blank.running = true;
        focusDeck.running = true;
        gamePoll.start();
        pollGame();
    }

    // Whether the lock screen is currently showing anything, as opposed to
    // being fully black. Drives SteamDeckLock's content opacity.
    property bool displaysAwake: false

    // --- why the desk goes black instead of going to sleep -------------------
    //
    // DPMS off on the AW3423DWF is not standby: the panel drops the DisplayPort
    // link entirely and reports itself DISCONNECTED. `dpms on` does not
    // reliably re-train the link afterwards, which is the same failure as the
    // "No DP-1 signal" seen after an output create/remove cycle. Two test runs
    // ended with a desk that could not be woken by any means short of a TTY.
    //
    // So the monitors stay powered and the lock surface simply fades its
    // content to nothing over a black background. On a QD-OLED that is the same
    // outcome the DPMS was chasing - black pixels are unlit pixels, so the panel
    // draws essentially nothing and cannot burn in - except the link stays up
    // and waking is instant and cannot fail.
    //
    // Set true to get the old behaviour on displays that handle DPMS properly
    // (an IPS panel or the TV, where the backlight is the thing worth killing).
    // The blank/wake subcommands in steamdeck_mode.sh are still there for it.
    property bool useDpms: false

    // Called by the lock surface on ANY input it receives.
    //
    // This used to hang off an IdleMonitor, which never fired: the desk stayed
    // dark through a whole test while the lock happily accepted a password
    // typed blind. Driving it from the surface is both simpler and provably
    // correct - the surface holds an exclusive keyboard grab and covers the
    // screen, so it is precisely the thing input is already reaching. DPMS
    // powers the output, not the input devices, so events arrive normally while
    // the screen is dark.
    function wakeDisplays(): void {
        reblankTimer.restart();
        if (root.displaysAwake)
            return;
        root.displaysAwake = true;
        if (root.useDpms)
            wake.running = true;
    }

    // Put the desk back to sleep if it was woken and then left alone - a knock,
    // the cat, a glance at the "still playing" text.
    property Timer reblankTimer: Timer {
        interval: 30000
        repeat: false
        onTriggered: {
            if (root.active && root.armed) {
                if (root.useDpms)
                    root.blank.running = true;
                root.displaysAwake = false;
            }
        }
    }

    // --- unlock / re-lock ---------------------------------------------------

    // Password accepted. Hand the desktop back but stay in the mode: Apollo and
    // the virtual output keep running, and idling re-locks.
    function unlock(): void {
        root.armed = false;
        // Light the desk back up unconditionally. Nothing else will: the lock
        // surface is about to go away, taking the input handlers that were
        // driving wakeDisplays() with it. Run even when useDpms is false, as a
        // catch-all in case anything else left a monitor powered down.
        wake.running = true;
        root.displaysAwake = true;
        reblankTimer.stop();
        focusDesk.running = true;
        persist();
        gamePoll.stop();
        relockMonitor.reset();
    }

    function relock(): void {
        if (!root.active || root.armed)
            return;
        armAndBlank();
    }



    function pollGame(): void {
        gameProc.running = true;
    }

    function persist(): void {
        const json = JSON.stringify({
            active: root.active,
            armed: root.armed,
            topazPausedByUs: root.topazPausedByUs
        });
        persistProc.command = ["sh", "-c",
            `mkdir -p '${root.stateDir}' && printf '%s' '${json}' > '${root.stateFile}'`];
        persistProc.running = true;
    }

    property Process persistProc: Process {
        stdout: SplitParser {}
    }

    // --- processes ----------------------------------------------------------

    property Process up: Process {
        command: [root.script, "up"]
        stdout: SplitParser {}
        onExited: code => {
            if (code !== 0)
                root.failed("Failed to start the Steamdeck stack");
        }
    }

    property Process down: Process {
        command: [root.script, "down"]
        stdout: SplitParser {}
    }

    property Process blank: Process {
        command: [root.script, "blank"]
        stdout: SplitParser {}
    }

    property Process wake: Process {
        command: [root.script, "wake"]
        stdout: SplitParser {}
    }

    // Focus follows the lock. While the desk is locked, focus sits on the
    // virtual output so anything Steam launches opens there and Apollo has
    // something to stream; the moment Harrison unlocks it comes back, because
    // focus on an invisible output means his keystrokes go somewhere he cannot
    // see.
    property Process focusDeck: Process {
        command: [root.script, "focus-deck"]
        stdout: SplitParser {}
    }

    property Process focusDesk: Process {
        command: [root.script, "focus-desk"]
        stdout: SplitParser {}
    }

    property Process gameProc: Process {
        command: ["sh", root.gameScript]
        stdout: SplitParser {
            onRead: data => root.gameName = (data || "").trim()
        }
        onExited: code => {
            // No game running prints nothing at all, so an empty read never
            // arrives and the old title would otherwise stick.
            if (code === 0 && !gameProc.stdout)
                return;
        }
    }

    // --- timers / monitors --------------------------------------------------

    property Timer graceTimer: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            root.graceLeft -= 1;
            if (root.graceLeft <= 0) {
                stop();
                root.armAndBlank();
            }
        }
    }

    // Refreshes the "currently playing" line while the lock is up.
    property Timer gamePoll: Timer {
        interval: 5000
        repeat: true
        onTriggered: root.pollGame()
    }

    // The 5 minute re-lock. Same reason for ignoring inhibitors.
    property var relockMonitor: IdleMonitor {
        id: relockMonitor

        function reset(): void {
            relockTimer.stop();
            relockElapsed = 0;
        }

        property int relockElapsed: 0

        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: {
            if (isIdle && root.active && !root.armed)
                relockTimer.start();
            else {
                relockTimer.stop();
                relockElapsed = 0;
            }
        }

        property Timer relockTimer: Timer {
            id: relockTimer
            interval: 1000
            repeat: true
            onTriggered: {
                relockMonitor.relockElapsed += 1;
                if (relockMonitor.relockElapsed >= root.relockSeconds) {
                    stop();
                    relockMonitor.relockElapsed = 0;
                    root.relock();
                }
            }
        }
    }

    // --- restore on start ---------------------------------------------------

    // Read back on start. A missing file is the normal case (mode never used, or
    // cleanly exited) and leaves every flag false.
    property Process restoreProc: Process {
        running: true
        command: ["cat", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw)
                    return;

                let st;
                try {
                    st = JSON.parse(raw);
                } catch (e) {
                    console.warn("SteamDeckService: unreadable state file:", e);
                    return;
                }

                root.active = st.active ?? false;
                root.armed = st.armed ?? false;
                root.topazPausedByUs = st.topazPausedByUs ?? false;

                if (!root.active)
                    return;

                // Hold the idle chain off again - CaffeineService restores its
                // own persisted value a moment after start and would otherwise
                // put us back to whatever it was before the mode began.
                caffeineReassert.start();

                if (root.armed)
                    root.applyArmedState();
            }
        }
        stderr: StdioCollector {}
    }

    property Timer caffeineReassert: Timer {
        interval: 800
        repeat: false
        onTriggered: {
            if (root.active)
                CaffeineService.inhibit = true;
        }
    }
}
