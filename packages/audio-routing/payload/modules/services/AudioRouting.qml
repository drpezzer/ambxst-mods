pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.services
import qs.modules.theme

/**
 * Per-application audio routing, playback and recording.
 *
 * Quickshell's Pipewire bindings expose nodes, volumes and the defaults,
 * but not the stream -> device assignment, so current routing is read from
 * `pactl -f json list sink-inputs/source-outputs` and changed with
 * `pactl move-sink-input` / `move-source-output`.
 *
 * pactl indexes streams by `object.serial`, which is NOT the PwNode id
 * (a node with id 165 is stream index 4954), so every lookup goes through
 * the node's own `object.serial` property.
 *
 * EasyEffects needs special handling throughout:
 *  - With "Process all output streams" enabled it moves every stream back
 *    into its own sink moments after any move, silently undoing per-app
 *    routes. The installer turns it off; `easyeffectsCapturing` reports it
 *    coming back so the UI can say why a route did not stick.
 *  - Its virtual sink's volume is never applied to anything: EasyEffects
 *    captures the sink's *monitor*, which PipeWire taps before volume
 *    (`monitor.channel-volumes` defaults to false). Volume for anything
 *    routed through EasyEffects therefore lives on the hardware device it
 *    feeds — `terminalSink()` resolves that.
 */
Singleton {
    id: root

    readonly property string eeSinkName: "easyeffects_sink"
    readonly property string eeSourceName: "easyeffects_source"

    // object.serial (string) -> device id (int), playback and recording.
    property var streamSinks: ({})
    property var streamSources: ({})
    // device id (int) -> device name (string)
    property var sinkIdNames: ({})
    property var sourceIdNames: ({})
    property string defaultSinkName: ""
    property string defaultSourceName: ""

    // True when EasyEffects is set to pull every output stream into its own
    // sink, which silently undoes any per-app route made here. Read from its
    // config rather than inferred from where streams sit, because routing every
    // app to EasyEffects on purpose is a legitimate setup.
    property bool easyeffectsCapturing: false
    property bool initialized: false

    signal routingRefreshed

    // ------------------------------------------------------------------
    // Device lists
    // ------------------------------------------------------------------

    // NVIDIA/HDMI pro-audio profiles show up as a wall of near-identical
    // sinks that are never the thing a user wants to pick from a notch.
    function isNoisySink(node): bool {
        const n = node?.name ?? "";
        return n.indexOf(".pro-output-") !== -1 || n.indexOf(".pro-input-") !== -1;
    }

    function isEasyEffects(node): bool {
        const n = node?.name ?? "";
        return n === root.eeSinkName || n === root.eeSourceName;
    }

    // EasyEffects first (it is a destination, not a device), then hardware.
    readonly property list<var> selectableSinks: {
        const usable = (Audio.outputDevices ?? []).filter(n => !root.isNoisySink(n));
        return usable.filter(n => root.isEasyEffects(n)).concat(usable.filter(n => !root.isEasyEffects(n)));
    }

    readonly property list<var> hardwareSinks: root.selectableSinks.filter(n => !root.isEasyEffects(n))

    // Sending every app through EasyEffects is a valid setup, so the master row
    // offers it too — but only while EasyEffects is pinned to a real device.
    // If it were following the system default, making it the default would
    // point it at itself, which it refuses to do.
    readonly property list<var> masterSinks: root.eeFollowsDefault ? root.hardwareSinks : root.selectableSinks

    // EasyEffects can never be its own output.
    readonly property list<var> easyeffectsTargetSinks: root.hardwareSinks

    // Recording mirrors playback: the EasyEffects virtual source (the
    // processed microphone) first, then real capture devices.
    readonly property list<var> selectableSources: {
        const usable = (Audio.inputDevices ?? []).filter(n => !root.isNoisySink(n));
        return usable.filter(n => root.isEasyEffects(n)).concat(usable.filter(n => !root.isEasyEffects(n)));
    }

    readonly property list<var> hardwareSources: root.selectableSources.filter(n => !root.isEasyEffects(n))

    readonly property list<var> masterSources: root.eeInputFollowsDefault ? root.hardwareSources : root.selectableSources

    // The description ("USB Audio Speakers") distinguishes devices that share
    // a nickname; this machine reports "USB Audio" for speakers, headphones
    // and S/PDIF alike, which is useless in a picker.
    function sinkLabel(node): string {
        if (!node)
            return "Unknown";
        if (root.isEasyEffects(node))
            return "EasyEffects";
        return node.description || node.nickname || node.name || "Unknown";
    }

    // Compact device name for use inside "EasyEffects (…)". ALSA UCM devices
    // are named alsa_output.<card>.HiFi__Speaker__sink, and that middle token
    // is a far better short label than the description ("USB Audio Speakers").
    // Non-UCM devices fall back to the full description.
    function shortSinkLabel(node): string {
        if (!node)
            return "";
        const match = /HiFi__(.+?)__(?:sink|source)$/.exec(node.name ?? "");
        if (match)
            return match[1].replace(/_/g, " ");
        return root.sinkLabel(node);
    }

    // Label for a routing destination. EasyEffects is a processing stage rather
    // than a device, so it carries the device it currently feeds.
    function routeLabel(node): string {
        if (!root.isEasyEffects(node))
            return root.sinkLabel(node);
        const target = (node?.name ?? "") === root.eeSourceName ? root.easyeffectsInputTarget : root.easyeffectsTarget;
        return target ? `EasyEffects (${root.shortSinkLabel(target)})` : "EasyEffects";
    }

    // ------------------------------------------------------------------
    // EasyEffects target devices
    // ------------------------------------------------------------------

    readonly property string eeScript: Qt.resolvedUrl("../../scripts/easyeffects_output.py").toString().replace("file://", "")

    property string eeConfiguredDevice: ""
    property bool eeFollowsDefault: true
    property string eeConfiguredInputDevice: ""
    property bool eeInputFollowsDefault: true
    // True while EasyEffects is being restarted to pick up a config change.
    property bool easyeffectsRestarting: false

    // The sink EasyEffects feeds. While it is set to follow the system default
    // its target is whatever the master row points at.
    readonly property var easyeffectsTarget: {
        if (root.eeFollowsDefault)
            return root.currentMasterSink();
        return (Audio.outputDevices ?? []).find(d => d.name === root.eeConfiguredDevice) ?? null;
    }

    // The microphone EasyEffects processes.
    readonly property var easyeffectsInputTarget: {
        if (root.eeInputFollowsDefault)
            return root.currentMasterSource();
        return (Audio.inputDevices ?? []).find(d => d.name === root.eeConfiguredInputDevice) ?? null;
    }

    FileView {
        id: eeConfigFile
        path: Quickshell.env("HOME") + "/.config/easyeffects/db/easyeffectsrc"
        watchChanges: true
        printErrors: false
        onLoaded: root.parseEeConfig()
        onFileChanged: reload()
    }

    function parseEeConfig() {
        let section = "";
        let device = "";
        let followsDefault = true;
        let inputDevice = "";
        let inputFollowsDefault = true;
        // Defaults to true in EasyEffects' own schema.
        let processAll = true;
        for (const raw of (eeConfigFile.text() ?? "").split("\n")) {
            const line = raw.trim();
            if (line.startsWith("[") && line.endsWith("]")) {
                section = line.slice(1, -1);
                continue;
            }
            if (line.indexOf("=") === -1)
                continue;
            const key = line.slice(0, line.indexOf("=")).trim();
            const value = line.slice(line.indexOf("=") + 1).trim();

            if (section === "StreamOutputs") {
                if (key === "outputDevice")
                    device = value;
                else if (key === "useDefaultOutputDevice")
                    followsDefault = value.toLowerCase() === "true";
            } else if (section === "StreamInputs") {
                if (key === "inputDevice")
                    inputDevice = value;
                else if (key === "useDefaultInputDevice")
                    inputFollowsDefault = value.toLowerCase() === "true";
            } else if (section === "EffectsPipelines" && key === "processAllOutputs") {
                processAll = value.toLowerCase() === "true";
            }
        }
        root.eeConfiguredDevice = device;
        root.eeFollowsDefault = followsDefault;
        root.eeConfiguredInputDevice = inputDevice;
        root.eeInputFollowsDefault = inputFollowsDefault;
        root.easyeffectsCapturing = processAll;
    }

    // EasyEffects reads its config only at startup, so retargeting means a
    // rewrite plus a service restart — a brief gap in any audio it is carrying.
    function setEasyEffectsTarget(sinkNode) {
        if (!sinkNode?.name || root.isEasyEffects(sinkNode))
            return;
        root.easyeffectsRestarting = true;
        eeTargetProcess.command = ["python3", root.eeScript, sinkNode.name];
        eeTargetProcess.running = true;
    }

    Process {
        id: eeTargetProcess
        running: false
        onExited: code => {
            if (code !== 0)
                console.warn("AudioRouting: EasyEffects config update failed, code", code);
            eeConfigFile.reload();
            // Give the service time to come back before dropping the notice.
            eeRestartTimer.restart();
        }
    }

    Timer {
        id: eeRestartTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.easyeffectsRestarting = false;
            root.refresh();
        }
    }

    function sinkIcon(node): string {
        if (root.isEasyEffects(node))
            return Icons.faders;
        // Name sniffing misfires here — the Blue mic's headphone jack is a
        // *sink* named "…Blue_Microphones…" — so capture devices are told
        // apart by node type instead.
        if (node && node.isSink === false)
            return Icons.mic;
        const n = (node?.name ?? "").toLowerCase();
        if (n.indexOf("headphone") !== -1 || n.indexOf("headset") !== -1)
            return Icons.headphones;
        return Icons.speakerHigh;
    }

    // ------------------------------------------------------------------
    // Current routing
    // ------------------------------------------------------------------

    function iconResolves(name): bool {
        return !!name && name !== "image-missing" && Quickshell.iconPath(name, true).length > 0;
    }

    // Desktop-entry icon for an app stream. Returns "" when nothing resolves so
    // the row can fall back to a themed glyph rather than render a blank gap.
    function appIconName(node): string {
        const props = node?.properties ?? {};
        const candidates = [props["application.name"], props["application.process.binary"], props["node.name"]].filter(c => !!c).map(c => String(c));

        for (const c of candidates) {
            const icon = AppSearch.getCachedIcon(c);
            if (root.iconResolves(icon))
                return icon;
        }

        // Streams rarely report the same string as the .desktop entry:
        // PipeWire says "Zen" where the entry is "Zen Browser" (icon
        // "zen-browser"), so fall back to matching on either being a prefix.
        for (const c of candidates) {
            const needle = c.toLowerCase();
            for (const app of (AppSearch.list ?? [])) {
                const name = (app.name ?? "").toLowerCase();
                if (!name)
                    continue;
                if ((name.startsWith(needle) || needle.startsWith(name)) && root.iconResolves(app.icon))
                    return app.icon;
            }
        }

        return "";
    }

    // Only populated while the node is bound by a PwObjectTracker; the audio
    // tab keeps one alive for every stream and device it lists.
    function serialOf(node): string {
        const s = node?.properties?.["object.serial"];
        return s === undefined || s === null ? "" : String(s);
    }

    // The sink a given app stream is currently playing into.
    function sinkForStream(node): var {
        const serial = root.serialOf(node);
        if (!serial)
            return null;
        const sinkId = root.streamSinks[serial];
        if (sinkId === undefined)
            return null;
        const name = root.sinkIdNames[sinkId];
        if (!name)
            return null;
        return (Audio.outputDevices ?? []).find(d => d.name === name) ?? null;
    }

    // The source a given app stream is recording from.
    function sourceForStream(node): var {
        const serial = root.serialOf(node);
        if (!serial)
            return null;
        const sourceId = root.streamSources[serial];
        if (sourceId === undefined)
            return null;
        const name = root.sourceIdNames[sourceId];
        if (!name)
            return null;
        return (Audio.inputDevices ?? []).find(d => d.name === name) ?? null;
    }

    // The hardware device a route actually ends at. EasyEffects is a virtual
    // stage whose own volume is never applied (it captures its sink's monitor,
    // which PipeWire taps pre-volume), so anything volume-related must resolve
    // through it to the device it feeds.
    function terminalSink(node): var {
        if (!root.isEasyEffects(node))
            return node;
        return (node?.name ?? "") === root.eeSourceName ? root.easyeffectsInputTarget : root.easyeffectsTarget;
    }

    // Whether anything is actually being processed right now. EasyEffects keeps
    // its configured output device either way — this is "is it in the path",
    // not "where does it point".
    readonly property bool easyeffectsInUse: {
        const map = root.streamSinks;
        for (const app of (Audio.outputAppNodes ?? [])) {
            if (!app?.ready)
                continue;
            const sink = root.sinkForStream(app);
            if (sink && root.isEasyEffects(sink))
                return true;
        }
        return false;
    }

    function currentMasterSink(): var {
        return (Audio.outputDevices ?? []).find(d => d.name === root.defaultSinkName) ?? Audio.sink ?? null;
    }

    function currentMasterSource(): var {
        return (Audio.inputDevices ?? []).find(d => d.name === root.defaultSourceName) ?? Audio.source ?? null;
    }

    // The device whose volume the master slider drives: the hardware end of
    // the default route. Attenuating the EasyEffects virtual sink does nothing
    // audible, so when the default is EasyEffects this is the device it feeds.
    readonly property var masterVolumeSink: root.terminalSink(root.currentMasterSink())
    readonly property var masterVolumeSource: root.terminalSink(root.currentMasterSource())

    // Playback grouped by the hardware device it ends at, for when apps are
    // split across devices: [{ device, count, viaEe }]. Streams through
    // EasyEffects land in the group of the device EasyEffects feeds, since
    // that device's volume is the one knob that affects them.
    readonly property list<var> deviceGroups: {
        const map = root.streamSinks;
        const groups = {};
        const order = [];
        for (const app of (Audio.outputAppNodes ?? [])) {
            if (!app?.ready)
                continue;
            const sink = root.sinkForStream(app);
            if (!sink)
                continue;
            const term = root.terminalSink(sink);
            if (!term?.name)
                continue;
            if (!groups[term.name]) {
                groups[term.name] = {
                    device: term,
                    count: 0,
                    viaEe: false
                };
                order.push(term.name);
            }
            groups[term.name].count++;
            if (root.isEasyEffects(sink))
                groups[term.name].viaEe = true;
        }
        return order.map(name => groups[name]);
    }

    // Apps are split across devices: the single master volume stops meaning
    // anything, and per-device rows take over.
    readonly property bool splitRouting: root.deviceGroups.length >= 2

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------

    function routeApp(node, sinkNode) {
        const serial = root.serialOf(node);
        if (!serial || !sinkNode?.name)
            return;
        moveProcess.command = ["pactl", "move-sink-input", serial, sinkNode.name];
        moveProcess.running = true;
    }

    function routeAppInput(node, sourceNode) {
        const serial = root.serialOf(node);
        if (!serial || !sourceNode?.name)
            return;
        moveProcess.command = ["pactl", "move-source-output", serial, sourceNode.name];
        moveProcess.running = true;
    }

    // Sets the default sink and moves every current stream, so picking a
    // device here moves everything audible rather than only future apps.
    // The name rides in as "$1" rather than being spliced into the script.
    function routeAll(sinkNode) {
        if (!sinkNode?.name)
            return;
        Audio.setDefaultSink(sinkNode);
        moveAllProcess.command = ["sh", "-c", `pactl set-default-sink "$1" && for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input "$i" "$1"; done`, "routeAll", sinkNode.name];
        moveAllProcess.running = true;
    }

    function routeAllInputs(sourceNode) {
        if (!sourceNode?.name)
            return;
        Audio.setDefaultSource(sourceNode);
        moveAllProcess.command = ["sh", "-c", `pactl set-default-source "$1" && for i in $(pactl list short source-outputs | cut -f1); do pactl move-source-output "$i" "$1"; done`, "routeAllInputs", sourceNode.name];
        moveAllProcess.running = true;
    }

    function initialize() {
        if (root.initialized)
            return;
        root.initialized = true;
        subscribeProcess.running = true;
        root.refresh();
    }

    property bool refreshQueued: false

    // A refresh requested while one is in flight runs again when it finishes,
    // rather than being dropped — the second request may carry a change the
    // running one started too early to see.
    function refresh() {
        if (refreshProcess.running)
            root.refreshQueued = true;
        else
            refreshProcess.running = true;
    }

    // ------------------------------------------------------------------
    // Processes
    // ------------------------------------------------------------------

    // One shell call keeps streams, devices and the defaults consistent with
    // each other; separate calls can interleave with a move.
    Process {
        id: refreshProcess
        command: ["sh", "-c", `printf '{"streams":%s,"sinks":%s,"recorders":%s,"sources":%s,"default":"%s","defaultSource":"%s"}' "$(pactl -f json list sink-inputs)" "$(pactl -f json list sinks)" "$(pactl -f json list source-outputs)" "$(pactl -f json list sources)" "$(pactl get-default-sink)" "$(pactl get-default-source)"`]
        running: false

        stdout: StdioCollector {
            id: refreshOut
        }

        onExited: code => {
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(() => refreshProcess.running = true);
            }
            if (code !== 0 || !refreshOut.text)
                return;
            try {
                const data = JSON.parse(refreshOut.text);
                const streams = {};
                const names = {};
                const recorders = {};
                const sourceNames = {};
                for (const s of (data.streams ?? [])) {
                    const serial = s.properties?.["object.serial"];
                    if (serial !== undefined)
                        streams[String(serial)] = s.sink;
                }
                for (const s of (data.sinks ?? []))
                    names[s.index] = s.name;
                for (const s of (data.recorders ?? [])) {
                    const serial = s.properties?.["object.serial"];
                    if (serial !== undefined)
                        recorders[String(serial)] = s.source;
                }
                for (const s of (data.sources ?? []))
                    sourceNames[s.index] = s.name;

                root.streamSinks = streams;
                root.sinkIdNames = names;
                root.streamSources = recorders;
                root.sourceIdNames = sourceNames;
                root.defaultSinkName = data.default ?? "";
                root.defaultSourceName = data.defaultSource ?? "";
                root.routingRefreshed();
            } catch (e) {
                console.warn("AudioRouting: failed to parse pactl output:", e);
            }
        }
    }

    // pactl emits an event for every stream change, so the list stays live
    // without polling. Debounced because a single move emits several.
    Process {
        id: subscribeProcess
        command: ["pactl", "subscribe"]
        running: false

        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("sink-input") !== -1 || line.indexOf("source-output") !== -1 || line.indexOf("server") !== -1 || line.indexOf("sink #") !== -1 || line.indexOf("source #") !== -1)
                    debounce.restart();
            }
        }

        // The subscription dies with pipewire-pulse; without a restart the tab
        // would silently stop updating for the rest of the session.
        onExited: {
            if (root.initialized)
                resubscribeTimer.restart();
        }
    }

    Timer {
        id: resubscribeTimer
        interval: 2000
        repeat: false
        onTriggered: {
            subscribeProcess.running = true;
            root.refresh();
        }
    }

    Timer {
        id: debounce
        interval: 120
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: moveProcess
        running: false
        onExited: code => {
            if (code !== 0)
                console.warn("AudioRouting: stream move failed with code", code);
            root.refresh();
            // EasyEffects reclaims a stream shortly after the move; re-check
            // so a silently reverted route can be reported to the user.
            verifyTimer.restart();
        }
    }

    Process {
        id: moveAllProcess
        running: false
        onExited: code => {
            root.refresh();
            verifyTimer.restart();
        }
    }

    Timer {
        id: verifyTimer
        interval: 900
        repeat: false
        onTriggered: root.refresh()
    }
}
