pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals

// Shared state for the bar's Bluetooth control. The button lives in the bar and
// the panel is drawn by UnifiedShellPanel, so open/close, scanning and the
// device split are held here rather than in either half.
Singleton {
    id: root

    // BlueZ names a device it has no name for after its own address, so a scan
    // fills up with beacons and randomised-MAC phones. Blueman hides these by
    // default (org.blueman.general hide-unnamed) and the list is unusable without
    // it — but only ever hide them from the discovered half, never from devices
    // already paired.
    function isUnnamed(device): bool {
        if (!device)
            return true;
        const name = (device.name ?? "").replace(/-/g, ":").toUpperCase();
        const address = (device.address ?? "").toUpperCase();
        return name === "" || name === "UNKNOWN" || name === address;
    }

    readonly property var knownDevices: BluetoothService.friendlyDeviceList.filter(d => d && (d.paired || d.connected))
    readonly property var newDevices: BluetoothService.friendlyDeviceList.filter(d => d && !d.paired && !d.connected && !root.isUnnamed(d))

    readonly property bool panelOpen: GlobalStates.bluetoothPanelVisible

    // Contributed by the bar button; the flyout writes GlobalStates directly.
    property bool buttonHovered: false
    readonly property bool pointerInside: buttonHovered || GlobalStates.bluetoothPanelHovered

    function openPanel(screenName: string, anchor: real): void {
        GlobalStates.bluetoothPanelScreenName = screenName;
        GlobalStates.bluetoothPanelAnchor = anchor;
        GlobalStates.bluetoothPanelVisible = true;

        BluetoothService.initialize();
        if (BluetoothService.enabled) {
            BluetoothService.updateDevices();
            BluetoothService.startDiscovery();
        }
    }

    function closePanel(): void {
        leaveTimer.stop();
        GlobalStates.bluetoothPanelVisible = false;
        GlobalStates.bluetoothPanelHovered = false;
        BluetoothService.stopDiscovery();
    }

    function toggle(screenName: string, anchor: real): void {
        if (GlobalStates.bluetoothPanelVisible && GlobalStates.bluetoothPanelScreenName === screenName)
            closePanel();
        else
            openPanel(screenName, anchor);
    }

    function setEnabled(value: bool): void {
        BluetoothService.setEnabled(value);
        if (value)
            powerOnKick.restart();
        else
            BluetoothService.stopDiscovery();
    }

    // bluetoothctl takes a moment to reflect a connect/disconnect.
    function refreshSoon(): void {
        refreshSoonTimer.restart();
    }

    // The panel closes on pointer-exit, but the pointer has to cross the seam
    // between button and panel, so exit is debounced.
    onPointerInsideChanged: {
        if (pointerInside)
            leaveTimer.stop();
        else if (GlobalStates.bluetoothPanelVisible)
            leaveTimer.restart();
    }

    Timer {
        id: leaveTimer
        interval: 400
        onTriggered: {
            if (!root.pointerInside)
                root.closePanel();
        }
    }

    // The adapter needs a moment after `power on` before it will accept a scan.
    Timer {
        id: powerOnKick
        interval: 700
        onTriggered: {
            if (BluetoothService.enabled && GlobalStates.bluetoothPanelVisible) {
                BluetoothService.updateDevices();
                BluetoothService.startDiscovery();
            }
        }
    }

    Timer {
        id: refreshSoonTimer
        interval: 800
        onTriggered: BluetoothService.updateDevices()
    }

    // A scan window is time-boxed, so reopen one as soon as it lapses rather than
    // polling on a fixed interval, which would leave the adapter idle for the
    // remainder of each tick. closePanel() clears the visible flag before it stops
    // discovery, so a deliberate close can't retrigger this.
    Connections {
        target: BluetoothService

        function onDiscoveringChanged(): void {
            if (!BluetoothService.discovering && GlobalStates.bluetoothPanelVisible && BluetoothService.enabled)
                rescanDelay.restart();
        }
    }

    Timer {
        id: rescanDelay
        interval: 400
        onTriggered: {
            if (GlobalStates.bluetoothPanelVisible && BluetoothService.enabled)
                BluetoothService.startDiscovery();
        }
    }

    // Safety net. openPanel() can land before the adapter's powered state has been
    // read back, and startDiscovery() silently no-ops while `enabled` is still
    // false — after which nothing retries, because the restart above only fires
    // when a scan *stops*, and none ever started. Opening the panel shortly after
    // login therefore left it scanning forever with an empty list. `running` is
    // bound to `enabled`, so this arms itself the moment the adapter is known.
    Timer {
        id: ensureScanning
        interval: 2000
        repeat: true
        running: GlobalStates.bluetoothPanelVisible && BluetoothService.enabled
        onTriggered: {
            if (!BluetoothService.discovering)
                BluetoothService.startDiscovery();
        }
    }

    // The service only polls the device list for the dashboard/launcher/overview,
    // so the panel drives its own refresh while open.
    Timer {
        id: refreshTimer
        interval: 3000
        repeat: true
        running: GlobalStates.bluetoothPanelVisible && BluetoothService.enabled
        onTriggered: BluetoothService.updateDevices()
    }
}
