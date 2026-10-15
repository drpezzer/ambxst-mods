pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

// Video Wallpaper Optimizer: hands video wallpapers to skwd-wall's renderer
// (https://github.com/liixini/skwd-wall) instead of playing them through
// QtMultimedia inside the shell.
//
// Ambxst stays in charge of everything else: the picker, the library, the
// per-screen choices and matugen. This service only watches what each screen
// should show. While any screen shows a video it keeps the skwd daemon
// running and gives it every screen's wallpaper (`skwd-helm apply FILE -o
// OUTPUT`), so a screen with an image next to one with a video stays right
// too. When no screen shows a video it stops the daemon, and Ambxst draws its
// images (and their transitions) itself again.
//
// VideoWallpaper.qml asks `offloads(path)` before it starts its own player;
// while that is true it plays nothing and only reports whether it wants to be
// paused (fullscreen window, game mode). If skwd is missing or keeps failing,
// `active` turns false and every VideoWallpaper starts its own player again.
//
// Options live in ~/.config/ambxst/video-wallpaper-optimizer.json:
//   enabled          false hands videos back to Ambxst's own player
//   stopWhenNoVideo  stop the skwd daemon while no screen shows a video
Singleton {
    id: root

    readonly property bool enabled: config.adapter.enabled
    property bool available: false      // skwd-helm and skwd-walld are on PATH
    property bool failed: false         // the daemon could not be reached; Ambxst plays videos itself
    readonly property bool active: enabled && available && !failed

    readonly property var manager: GlobalStates.wallpaperManager
    readonly property var videoExtensions: ["mp4", "webm", "mov", "avi", "mkv"]

    // Screen name -> the file that screen should show.
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
    readonly property bool anyVideo: Object.keys(desired).some(name => isVideo(desired[name]))

    property var applied: ({})          // screen name -> file skwd was last told to show
    property bool daemonUp: false
    property bool started: false        // this service started the daemon and owns stopping it
    property var pauseWanted: ({})      // screen name -> true while that screen's VideoWallpaper wants a pause
    property bool skwdPaused: false

    function isVideo(path) {
        if (!path)
            return false;
        const ext = String(path).toLowerCase().split('.').pop();
        return videoExtensions.indexOf(ext) !== -1;
    }

    // Asked by VideoWallpaper before it plays `path` itself.
    function offloads(path) {
        return active && isVideo(path);
    }

    // VideoWallpaper reports here instead of pausing its own player. skwd can
    // only pause every output at once, so it pauses when every screen that
    // shows a video wants it to.
    function reportPause(screenName, wantPause) {
        if (!screenName)
            return;
        const next = Object.assign({}, pauseWanted);
        if (wantPause)
            next[screenName] = true;
        else
            delete next[screenName];
        pauseWanted = next;
        pauseDebounce.restart();
    }

    function updatePause() {
        if (!active || !daemonUp)
            return;
        const videoScreens = Object.keys(desired).filter(name => isVideo(desired[name]));
        const want = videoScreens.length > 0 && videoScreens.every(name => pauseWanted[name] === true);
        if (want === skwdPaused)
            return;
        skwdPaused = want;
        run(["skwd-helm", want ? "pause" : "resume"], null);
    }

    onDesiredChanged: syncDebounce.restart()
    onActiveChanged: syncDebounce.restart()
    // Turning the optimizer back on gives skwd another chance after a failure.
    onEnabledChanged: if (enabled) failed = false

    Timer {
        id: syncDebounce
        interval: 400
        onTriggered: root.sync()
    }

    Timer {
        id: pauseDebounce
        interval: 250
        onTriggered: root.updatePause()
    }

    function sync() {
        if (!manager)
            return;
        if (!active) {
            if (started)
                stopDaemon();
            return;
        }
        if (!anyVideo) {
            // Stopped, Ambxst draws the images. Kept running (stopWhenNoVideo
            // off), it keeps showing what each screen should show, images too.
            if (config.adapter.stopWhenNoVideo) {
                if (started)
                    stopDaemon();
                return;
            }
            if (!daemonUp)
                return;
        }
        if (!daemonUp) {
            startDaemon(0);
            return;
        }
        for (const name in desired) {
            if (applied[name] !== desired[name])
                applyTo(name, desired[name], 0);
        }
        pauseDebounce.restart();
    }

    function applyTo(screenName, file, attempt) {
        const next = Object.assign({}, applied);
        next[screenName] = file;
        applied = next;
        run(["skwd-helm", "apply", file, "-o", screenName], code => {
            if (code === 0)
                return;
            // Exit 3: the daemon is not answering (stopped, or still starting).
            const again = Object.assign({}, root.applied);
            delete again[screenName];
            root.applied = again;
            if (code === 3 && attempt < 4) {
                root.daemonUp = false;
                root.startDaemon(attempt + 1);
                return;
            }
            console.warn("VideoWallpaperOptimizer: skwd-helm apply failed with exit code", code, "for", screenName, file, "- playing videos in Ambxst instead");
            root.failed = true;
            root.stopDaemon();
        });
    }

    function startDaemon(attempt) {
        if (attempt > 4) {
            console.warn("VideoWallpaperOptimizer: skwd-walld did not start - playing videos in Ambxst instead");
            failed = true;
            stopDaemon();
            return;
        }
        started = true;
        run(["systemctl", "--user", "start", "skwd-walld.service"], code => {
            if (code !== 0) {
                console.warn("VideoWallpaperOptimizer: could not start skwd-walld.service (exit", code + ") - playing videos in Ambxst instead");
                root.failed = true;
                return;
            }
            // skwd restores its own last wallpaper on start; read what it shows
            // so nothing is applied twice, then bring every screen in line.
            daemonWait.attempt = attempt;
            daemonWait.restart();
        });
    }

    Timer {
        id: daemonWait
        property int attempt: 0
        interval: 1200
        onTriggered: root.readCurrent(() => {
            root.daemonUp = true;
            root.skwdPaused = false;
            root.sync();
        }, attempt)
    }

    function stopDaemon() {
        started = false;
        daemonUp = false;
        applied = ({});
        skwdPaused = false;
        run(["systemctl", "--user", "stop", "skwd-walld.service"], null);
    }

    // `skwd-helm current` prints "OUTPUT<TAB>PATH" per output.
    function readCurrent(done, attempt) {
        run(["skwd-helm", "current"], (code, out) => {
            if (code === 3) {
                if (attempt < 4) {
                    daemonWait.attempt = attempt + 1;
                    daemonWait.restart();
                } else {
                    root.startDaemon(5);
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
            done();
        });
    }

    // A small queue: one skwd-helm / systemctl call at a time, in order.
    property var queue: []
    function run(command, onDone) {
        queue = queue.concat([{
                command: command,
                onDone: onDone
            }]);
        if (!runner.running)
            runNext();
    }
    function runNext() {
        if (queue.length === 0 || runner.running || runner.job)
            return;
        const job = queue[0];
        queue = queue.slice(1);
        runner.job = job;
        runner.command = job.command;
        runner.running = true;
    }

    // A job finishes once the process has exited AND its output is read,
    // whichever comes last.
    Process {
        id: runner
        property var job: null
        property int exitCode: -1
        property bool exited: false
        property bool outDone: false
        onRunningChanged: {
            if (running) {
                exited = false;
                outDone = false;
            }
        }
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
                console.log("VideoWallpaperOptimizer: skwd-wall is not installed (skwd-helm / skwd-walld not on PATH); videos play in Ambxst");
                return;
            }
            // A daemon left running by an earlier shell (a reload) is ours to
            // manage too: stopped when no screen shows a video any more.
            root.run(["systemctl", "--user", "is-active", "--quiet", "skwd-walld.service"], code => {
                if (code === 0)
                    root.started = true;
                syncDebounce.restart();
            });
        }
    }

    FileView {
        id: config
        path: Quickshell.env("HOME") + "/.config/ambxst/video-wallpaper-optimizer.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        adapter: JsonAdapter {
            property bool enabled: true
            property bool stopWhenNoVideo: true
        }
    }
}
