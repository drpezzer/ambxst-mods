pragma Singleton
import QtQuick
import Quickshell
import qs.modules.services

// settings-float mod: holds the mod's settings so they are known BEFORE the
// Settings window is created. SettingsWindow.qml is loaded on open and maps
// immediately, so reading the settings from inside it would be too late for
// the fixed-size hint that makes the compositor float the window at map time.
// shell.qml touches `enabled` once at startup to instantiate this singleton.
Singleton {
    id: root

    readonly property string modId: "drpezzer.settings-float"

    property bool enabled: true
    property real widthPercent: 41
    property real heightPercent: 66
    property bool loaded: false

    function applyValues(values) {
        if (!values) return;
        if (values.enabled !== undefined) root.enabled = !!values.enabled;
        const wp = Number(values.widthPercent), hp = Number(values.heightPercent);
        if (!isNaN(wp) && wp > 0) root.widthPercent = wp;
        if (!isNaN(hp) && hp > 0) root.heightPercent = hp;
    }

    function load() {
        if (typeof ModsService === "undefined" || typeof ModsService.getSettings !== "function") return;
        ModsService.getSettings(root.modId, (settings, error) => {
            if (error || !settings) return;
            root.applyValues(settings.values);
            root.loaded = true;
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId !== root.modId) return;
            const values = {};
            values[key] = value;
            root.applyValues(values);
        }
    }

    Component.onCompleted: load()
}
