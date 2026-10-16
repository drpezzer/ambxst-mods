pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

// Ambxst Skwd-wall: skwd-wall (https://github.com/liixini/skwd-wall) draws every
// wallpaper; Ambxst keeps the picker, the library, per-screen choices, rotation
// and matugen colours.
//
// This service watches what each screen should show and keeps the skwd daemon
// in step (`skwd-helm apply FILE -o OUTPUT`). Ambxst's own VideoWallpaper asks
// `offloads(path)` before starting its QtMultimedia player and stays idle while
// skwd plays the file. The wallpaper settings (transition, duration, when to
// pause) are written into skwd's own config, ~/.config/skwd-wall-v2/config.json,
// which the daemon re-reads on its own.
//
// If skwd is missing or keeps failing, `active` turns false and Ambxst draws
// and plays everything itself again.
//
// Options: ~/.config/ambxst/skwd-wall.json
//   enabled   false hands every wallpaper back to Ambxst and stops skwd
Singleton {
    id: root

    readonly property bool enabled: options.adapter.enabled
    property bool available: false      // skwd-helm and skwd-walld are on PATH
    property bool failed: false         // the daemon could not be reached
    readonly property bool active: enabled && available && !failed

    readonly property var manager: GlobalStates.wallpaperManager
    readonly property var videoExtensions: ["mp4", "webm", "mov", "avi", "mkv", "gif"]

    // ── skwd's transitions (wall-proto/src/transitions.rs, skwd-deck) ──
    // `instant` is ours: skwd's `transition.enabled = false`.
    readonly property var families: [
        { key: "all", title: "All" },
        { key: "fade", title: "Fade", desc: "Dissolves and blends, no geometry" },
        { key: "wipe", title: "Wipe", desc: "A shape or edge sweeps across the screen" },
        { key: "warp", title: "Warp", desc: "The image bends, stretches or ripples" },
        { key: "break", title: "Break up", desc: "The image shatters, pixelates or smears" },
        { key: "sand", title: "Sand", desc: "Every pixel becomes a grain and flies into a shape" }
    ]
    readonly property var transitions: [
        { key: "random", family: "random", title: "Random", desc: "A different transition every time" },
        { key: "crossfade", family: "fade", title: "Crossfade", desc: "Smooth dissolve from old to new" },
        { key: "fadecolor", family: "fade", title: "Fade Through Black", desc: "Fades to black, then the new image fades up" },
        { key: "colour-distance", family: "fade", title: "Colour Match", desc: "Areas whose colours already match swap first" },
        { key: "perlin", family: "fade", title: "Noise Dissolve", desc: "Cloudy noise patches fill in with the new image" },
        { key: "pixelfade-wave", family: "fade", title: "Pixel Wave", desc: "Pixelated band sweeps top-left to bottom-right" },
        { key: "soft-warp-fade", family: "fade", title: "Soft Warp Fade", desc: "Gentle shimmering crossfade" },
        { key: "circle-crop", family: "wipe", title: "Circle Crop", desc: "Old shrinks into a centre circle, new circle grows back" },
        { key: "iris", family: "wipe", title: "Iris Open", desc: "Circle opens from centre with colour-fringed edge" },
        { key: "crosshatch", family: "wipe", title: "Crosshatch", desc: "Random thin rows and columns of new flick in" },
        { key: "directional", family: "wipe", title: "Push Up", desc: "Old slides up and off, new pushes in from below" },
        { key: "directional-scaled", family: "wipe", title: "Card Slide", desc: "Shrinks to a card, slides up, new card rises in" },
        { key: "directional-wipe", family: "wipe", title: "Diagonal Wipe", desc: "Soft diagonal wipe from bottom-left to top-right" },
        { key: "polka-dots-curtain", family: "wipe", title: "Polka Dots", desc: "Growing dots fill in from the top-left corner" },
        { key: "puzzle-right", family: "wipe", title: "Tile Flip", desc: "4x4 tiles flip sideways at random to the new" },
        { key: "randomsquares", family: "wipe", title: "Random Squares", desc: "Grid squares switch to the new at random" },
        { key: "crosswarp", family: "warp", title: "Cross Warp", desc: "Zooming warp sweeps across from right to left" },
        { key: "heat-melt", family: "warp", title: "Heat Melt", desc: "Dark areas melt in from bottom-right corner" },
        { key: "morph", family: "warp", title: "Colour Morph", desc: "Pixels drift along their colours while blending" },
        { key: "zoom-blur-pull", family: "warp", title: "Zoom Blur Pull", desc: "Radial zoom blur whose focus drifts left to right" },
        { key: "chromatic-bloom", family: "break", title: "Chromatic Bloom", desc: "RGB fringes push out from centre, glow, quick swap" },
        { key: "glitch", family: "break", title: "Jitter Split", desc: "Whole frame jitters with RGB split while fading" },
        { key: "glitch-displace", family: "break", title: "Grey Glitch Snap", desc: "Old smears to a grey ghost, snaps to warped new" },
        { key: "parametric-glitch", family: "break", title: "Wave Fold", desc: "Old folds into wavy colour-keyed bands, fades out" },
        { key: "ink-splash", family: "break", title: "Ink Splash", desc: "Ragged ink blot spreads from centre with dark rim" },
        { key: "inkwell-drop", family: "break", title: "Inkwell Drop", desc: "Rippling ring spreads from a drop left of centre" },
        { key: "mosaic-tumble", family: "break", title: "Mosaic Pan", desc: "Zooms out to a tile wall, pans, zooms into new" },
        { key: "pixelate", family: "break", title: "Pixelate", desc: "Pixelates to a coarse grid, swaps, then sharpens" },
        { key: "plasma-flow", family: "break", title: "Plasma Flow", desc: "Liquid wobble warp while crossfading" },
        { key: "smoke", family: "break", title: "Smoke Reveal", desc: "Smoky wisps eat inward from the edges to centre" },
        { key: "voronoi-shatter", family: "break", title: "Voronoi Shatter", desc: "Cell shards slide the old away, revealing new" },
        { key: "sand-bloom", family: "sand", title: "Sand Bloom", desc: "Old blows away edge-first, new sand lands centre-out" },
        { key: "sand-donut", family: "sand", title: "Sand Donut", desc: "Sand spins round a centre ring, recolours, returns" },
        { key: "sand-galaxy", family: "sand", title: "Sand Galaxy", desc: "Sand swirls into a flat spinning spiral disk" },
        { key: "sand-globe", family: "sand", title: "Sand Globe", desc: "Sand wraps into a spinning globe, then lands" },
        { key: "sand-helix", family: "sand", title: "Sand Helix", desc: "Double helix of sand pours down the centre" },
        { key: "sand-maelstrom", family: "sand", title: "Sand Maelstrom", desc: "Sand churns through a ring vortex both ways" },
        { key: "sand-mobius", family: "sand", title: "Sand Mobius", desc: "Sand twists into a rotating Mobius band" },
        { key: "sand-murmuration", family: "sand", title: "Sand Flock", desc: "Sand flocks out to the right, new flock from left" },
        { key: "sand-tornado", family: "sand", title: "Sand Tornado", desc: "Sand spins up a swaying funnel, then settles" },
        { key: "instant", family: "instant", title: "Instant", desc: "No transition, a straight swap" }
    ]

    function transitionInfo(key) {
        for (let i = 0; i < transitions.length; i++)
            if (transitions[i].key === key)
                return transitions[i];
        return transitions[0];
    }

    // Styles the original Wallpaper Transitions mod saved, mapped to skwd's.
    function migrateStyle(style) {
        const map = {
            circleOut: "iris",
            circleIn: "circle-crop",
            slideLeft: "directional",
            slideRight: "directional",
            slideUp: "directional",
            slideDown: "directional",
            zoomFade: "zoom-blur-pull",
            pulse: "soft-warp-fade",
            none: "instant"
        };
        if (map[style])
            return map[style];
        for (let i = 0; i < transitions.length; i++)
            if (transitions[i].key === style)
                return style;
        return "random";
    }

    // ── what each screen shows ─────────────────────────────────────────
    readonly property var desired: {
        const m = root.manager;
        const out = {};
        if (!m)
            return out;
        const per = m.perScreenWallpapers || {};
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            const name = screens[i].name;
            const file = per[name] || m.currentWallpaper || "";
            if (file)
                out[name] = file;
        }
        return out;
    }

    property var applied: ({})          // screen name -> file skwd was last told to show
    property bool daemonUp: false
    property bool started: false        // this service started the daemon and owns stopping it

    function isMoving(path) {
        if (!path)
            return false;
        const ext = String(path).toLowerCase().split('.').pop();
        return videoExtensions.indexOf(ext) !== -1;
    }

    // Asked by VideoWallpaper before it plays `path` itself.
    function offloads(path) {
        return active && isMoving(path);
    }

    onDesiredChanged: syncDebounce.restart()
    onActiveChanged: {
        syncDebounce.restart();
        if (active)
            writeSkwdConfig();
    }
    // Turning it back on gives skwd another chance after a failure.
    onEnabledChanged: if (enabled) failed = false

    Timer {
        id: syncDebounce
        interval: 300
        onTriggered: root.sync()
    }

    function sync() {
        if (!manager)
            return;
        if (!active) {
            if (started)
                stopDaemon();
            return;
        }
        if (!daemonUp) {
            startDaemon(0);
            return;
        }
        for (const name in desired) {
            if (applied[name] !== desired[name])
                applyTo(name, desired[name]);
        }
    }

    function applyTo(screenName, file) {
        const next = Object.assign({}, applied);
        next[screenName] = file;
        applied = next;
        run(["skwd-helm", "apply", file, "-o", screenName], code => {
            if (code === 0)
                return;
            const again = Object.assign({}, root.applied);
            delete again[screenName];
            root.applied = again;
            // Exit 3: the daemon is not answering (stopped, or still starting).
            if (code === 3) {
                root.daemonUp = false;
                root.startDaemon(0);
                return;
            }
            console.warn("SkwdWall: skwd-helm apply failed with exit code", code, "for", screenName, file, "- Ambxst draws wallpapers itself");
            root.failed = true;
            root.stopDaemon();
        });
    }

    property int startAttempts: 0
    function startDaemon(attempt) {
        if (attempt === 0 && startAttempts > 8) {
            console.warn("SkwdWall: skwd-walld keeps failing - Ambxst draws wallpapers itself");
            failed = true;
            stopDaemon();
            return;
        }
        startAttempts++;
        started = true;
        writeSkwdConfig();
        run(["systemctl", "--user", "start", "skwd-walld.service"], code => {
            if (code !== 0) {
                console.warn("SkwdWall: could not start skwd-walld.service (exit", code + ") - Ambxst draws wallpapers itself");
                root.failed = true;
                root.started = false;
                return;
            }
            daemonWait.attempt = attempt;
            daemonWait.restart();
        });
    }

    Timer {
        id: daemonWait
        property int attempt: 0
        interval: 700
        onTriggered: root.readCurrent(attempt)
    }

    // skwd restores its own last wallpapers on start: read what it shows so
    // nothing is applied twice, then bring every screen in line.
    function readCurrent(attempt) {
        run(["skwd-helm", "current"], (code, out) => {
            if (code === 3) {
                if (attempt < 10) {
                    daemonWait.attempt = attempt + 1;
                    daemonWait.restart();
                } else {
                    console.warn("SkwdWall: skwd-walld did not answer - Ambxst draws wallpapers itself");
                    root.failed = true;
                    root.stopDaemon();
                }
                return;
            }
            const seen = {};
            if (code === 0) {
                String(out).split("\n").forEach(line => {
                    const tab = line.indexOf("\t");
                    if (tab > 0)
                        seen[line.substring(0, tab)] = line.substring(tab + 1).trim();
                });
            }
            root.applied = seen;
            root.daemonUp = true;
            root.startAttempts = 0;
            root.sync();
        });
    }

    function stopDaemon() {
        started = false;
        daemonUp = false;
        applied = ({});
        run(["systemctl", "--user", "stop", "skwd-walld.service"], null);
    }

    // ── settings → skwd's config.json ──────────────────────────────────
    readonly property string transitionStyle: migrateStyle(GlobalStates.wallpaperTransitionStyle)
    readonly property int transitionDuration: Math.max(50, Math.min(10000, GlobalStates.wallpaperTransitionDuration))
    readonly property string pauseMode: GlobalStates.wallpaperPauseMode
    readonly property string pauseScope: GlobalStates.wallpaperPauseScope
    onTransitionStyleChanged: configDebounce.restart()
    onTransitionDurationChanged: configDebounce.restart()
    onPauseModeChanged: configDebounce.restart()
    onPauseScopeChanged: configDebounce.restart()

    Timer {
        id: configDebounce
        interval: 250
        onTriggered: root.writeSkwdConfig()
    }

    function writeSkwdConfig() {
        if (!available)
            return;
        skwdConfig.reload();
        let cfg = {};
        try {
            const text = skwdConfig.text();
            if (text && text.trim().length > 0)
                cfg = JSON.parse(text);
        } catch (e) {
            // A config skwd itself cannot read either: leave it alone.
            console.warn("SkwdWall: could not read skwd's config.json, not changing it:", e);
            return;
        }
        const before = JSON.stringify(cfg);
        function put(path, value) {
            const parts = path.split(".");
            let node = cfg;
            for (let i = 0; i < parts.length - 1; i++) {
                if (typeof node[parts[i]] !== "object" || node[parts[i]] === null || Array.isArray(node[parts[i]]))
                    node[parts[i]] = {};
                node = node[parts[i]];
            }
            node[parts[parts.length - 1]] = value;
        }
        const instant = transitionStyle === "instant";
        put("transition.enabled", !instant);
        if (!instant)
            put("transition.shader", transitionStyle);
        put("transition.durationMs", transitionDuration);
        // Pause mode: fullscreen | maximized | never; scope: perScreen | allScreens.
        put("playback.fullscreen", pauseMode !== "never");
        put("playback.maximized", pauseMode === "maximized");
        put("playback.fullscreenScope", pauseScope === "allScreens" ? "all" : "display");
        if (JSON.stringify(cfg) === before)
            return;
        skwdConfig.setText(JSON.stringify(cfg, null, 2) + "\n");
    }

    FileView {
        id: skwdConfig
        path: Quickshell.env("HOME") + "/.config/skwd-wall-v2/config.json"
        blockLoading: true
        printErrors: false
    }

    // ── a small queue: one skwd-helm / systemctl call at a time ────────
    property var queue: []
    function run(command, onDone) {
        queue = queue.concat([{
                command: command,
                onDone: onDone
            }]);
        runNext();
    }
    function runNext() {
        if (queue.length === 0 || runner.running || runner.job)
            return;
        const job = queue[0];
        queue = queue.slice(1);
        runner.job = job;
        runner.exited = false;
        runner.outDone = false;
        runner.command = job.command;
        runner.running = true;
    }

    // A job finishes once the process has exited AND its output is read.
    Process {
        id: runner
        property var job: null
        property int exitCode: -1
        property bool exited: false
        property bool outDone: false
        stdout: StdioCollector {
            id: runnerOut
            onStreamFinished: {
                runner.outDone = true;
                runner.finish();
            }
        }
        onExited: (code, exitStatus) => {
            runner.exitCode = code;
            runner.exited = true;
            runner.finish();
        }
        function finish() {
            if (!exited || !outDone || !job)
                return;
            const done = job;
            job = null;
            if (done.onDone)
                done.onDone(exitCode, runnerOut.text);
            Qt.callLater(root.runNext);
        }
    }

    // Is skwd installed? Checked once at start.
    Process {
        id: probe
        command: ["sh", "-c", "command -v skwd-helm >/dev/null && command -v skwd-walld >/dev/null"]
        running: true
        onExited: exitCode => {
            root.available = exitCode === 0;
            if (!root.available) {
                console.log("SkwdWall: skwd-wall is not installed (skwd-helm / skwd-walld not on PATH); Ambxst draws wallpapers itself");
                return;
            }
            // A daemon left running by an earlier shell (a reload) is ours too.
            root.run(["systemctl", "--user", "is-active", "--quiet", "skwd-walld.service"], code => {
                if (code === 0)
                    root.started = true;
                syncDebounce.restart();
            });
        }
    }

    FileView {
        id: options
        path: Quickshell.env("HOME") + "/.config/ambxst/skwd-wall.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        adapter: JsonAdapter {
            property bool enabled: true
        }
    }
}
