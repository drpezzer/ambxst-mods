pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// roadie: the wired side of the network, for the notch's quick controls.
//
// Stock Ambxst knows one thing about Ethernet -- whether a wired device is
// connected -- and offers nothing to do with it: the only network control in
// the dashboard is the Wi-Fi switch. On a desk that is always on a cable that
// switch is beside the point. This keeps the list of wired devices
// NetworkManager manages and turns them on and off, so the quick controls can
// show an Ethernet switch next to the Wi-Fi one.
//
// The switch is there while a cable is in, connected or not:
//
//   unavailable   no carrier, the cable is out      -> no switch
//   disconnected  cable in, turned off              -> switch, off
//   connecting    cable in, getting an address      -> switch, on
//   connected     cable in, up                      -> switch, on
//
// "Is it connected" could not decide that: switching it off would then take
// the switch away with nothing left to switch it back on with.
//
// Off is `nmcli device disconnect`, which also stops NetworkManager from
// bringing the device straight back up; on is `nmcli device connect`. Nothing
// is stored: after a reboot NetworkManager connects a plugged-in cable as it
// always does.
Singleton {
    id: root

    // Settings > Roadie, "Ethernet switch in the notch". Off: nothing here
    // runs.
    readonly property bool enabled: RoadieSettings.ethernetButton

    // [{ device, state, connection }] for every managed wired device.
    property var devices: []

    // The ones with a cable in.
    readonly property var plugged: root.devices.filter(d => d.state !== "unavailable")
    readonly property bool present: root.plugged.length > 0
    readonly property bool connected: root.plugged.some(d => d.state === "connected")
    readonly property bool connecting: root.plugged.some(d => d.state === "connecting")
    readonly property string connectionName: {
        const up = root.plugged.find(d => d.state === "connected" && d.connection);
        return up ? up.connection : "";
    }

    // What was last asked for ("on" / "off"), until NetworkManager reports it
    // or gives up, so the switch answers the click at once.
    property string pending: ""
    readonly property bool on: root.pending !== "" ? root.pending === "on" : (root.connected || root.connecting)

    function setOn(value: bool): void {
        const want = !!value;
        if (want) {
            const down = root.plugged.filter(d => d.state === "disconnected");
            if (down.length === 0)
                return;
            // One device per call: `device connect` takes a single interface.
            for (let i = 0; i < down.length; i++)
                Quickshell.execDetached(["nmcli", "device", "connect", down[i].device]);
        } else {
            const up = root.plugged.filter(d => d.state === "connected" || d.state === "connecting");
            if (up.length === 0)
                return;
            Quickshell.execDetached(["nmcli", "device", "disconnect"].concat(up.map(d => d.device)));
        }
        root.pending = want ? "on" : "off";
        pendingTimer.restart();
    }

    function toggle(): void {
        root.setOn(!root.on);
    }

    function refresh(): void {
        if (!root.enabled)
            return;
        if (listProcess.running) {
            root.refreshAgain = true;
            return;
        }
        listProcess.running = true;
    }

    // A change that arrived while a listing was already running.
    property bool refreshAgain: false

    // `nmcli -t` separates fields with colons and escapes the ones inside a
    // field with a backslash.
    function splitTerse(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    function parse(text: string): void {
        const next = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const f = root.splitTerse(lines[i]);
            if (f.length < 3 || f[1] !== "ethernet")
                continue;
            // "connected (externally)", "connecting (getting IP configuration)"
            // and the like: the first word is the state.
            const state = f[2].split(" ")[0];
            // Not NetworkManager's to switch (a container's veth, say).
            if (state === "unmanaged")
                continue;
            next.push({
                device: f[0],
                state: state,
                connection: f[3] || ""
            });
        }
        if (JSON.stringify(next) !== JSON.stringify(root.devices))
            root.devices = next;

        // The request has landed once the devices agree with it.
        if (root.pending === "on" && (root.connected || !root.present))
            root.pending = "";
        else if (root.pending === "off" && !root.connected && !root.connecting)
            root.pending = "";
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.devices = [];
            root.pending = "";
        }
    }

    Component.onCompleted: {
        root.refresh();
        reapProcess.running = true;
    }

    // Housekeeping, whatever the switch says: Ambxst's daemon leaves its
    // `nmcli monitor` behind on every reload (see the script). This runs once
    // per shell start, a couple of seconds in, when the daemon that owned the
    // last one is gone -- so there is never more than the one in use.
    readonly property string reapScript: Qt.resolvedUrl("roadie_nmcli_reap.sh").toString().replace(/^file:\/\//, "")
    property Process reapProcess: Process {
        command: ["sh", root.reapScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = this.text.split("\n").filter(line => line.indexOf("reaped ") === 0).length;
                if (n > 0)
                    console.log("RoadieEthernet: ended", n, "leftover nmcli monitor" + (n === 1 ? "" : "s"), "of an earlier Ambxst daemon");
            }
        }
    }

    property Timer pendingTimer: Timer {
        // Long enough for DHCP on a slow network; after that the switch shows
        // whatever is true.
        interval: 15000
        onTriggered: root.pending = ""
    }

    // NetworkManager reports a change in several lines; one listing covers
    // them all.
    property Timer refreshDebounce: Timer {
        interval: 200
        onTriggered: root.refresh()
    }

    property Process listProcess: Process {
        // The state names are matched as words, so not in the user's language.
        environment: ({
                LC_ALL: "C"
            })
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
        onExited: {
            if (root.refreshAgain) {
                root.refreshAgain = false;
                root.refreshDebounce.restart();
            }
        }
    }

    // Every NetworkManager event, a cable going in or out included: Ambxst's
    // daemon already streams one state per event to NetworkService, which
    // counts them (stateSerial, roadie's one line there). Listening to that
    // rather than running an `nmcli monitor` of its own: a long-lived child
    // outlives the shell on every restart.
    property Connections watcher: Connections {
        target: root.enabled ? NetworkService : null
        function onStateSerialChanged() {
            root.refreshDebounce.restart();
        }
    }

    // While a click is being carried out, look again every second as well,
    // so the switch settles even if an event goes missing.
    property Timer pendingPoll: Timer {
        interval: 1000
        repeat: true
        running: root.pending !== ""
        onTriggered: root.refresh()
    }
}
