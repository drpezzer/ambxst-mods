pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.config

// Ambxst Roadie (drpezzer.roadie): Settings > Roadie. Every option of the mod
// lives here (RoadieSettings, ~/.config/ambxst/roadie.json), and everything
// applies as it is changed.
//
// Three groups, one at a time, behind the switch at the top of the page:
//   Features       what Roadie does, each with a switch. Off is what plain
//                  Ambxst does there; the bug fixes have no switch.
//   Behaviours     how the features that are ON behave.
//   Customization  durations, sizes and the farewell quotes of the features
//                  that are ON.
// The second and third only list what belongs to a feature that is switched
// on, so a page never shows a knob that does nothing. The page opens on
// Features the first time and on the group used last after that (kept in
// roadie.json with everything else, so it outlives the window and a reload).
Item {
    id: root

    property int maxContentWidth: 480
    property string currentSection: ""

    readonly property int pageWidth: Math.min(root.width - 16, root.maxContentWidth)
    // The group on show.
    readonly property int tab: RoadieSettings.page
    readonly property var tabNames: ["Features", "Behaviours", "Customization"]

    // What BarContent derives when the bar slide is left on automatic.
    readonly property int animBase: Config.animDuration !== undefined ? Config.animDuration : 300
    readonly property bool hasFrame: (Config.bar && Config.bar.frameEnabled !== undefined) ? Config.bar.frameEnabled : false
    readonly property bool containBar: hasFrame && ((Config.bar && Config.bar.containBar !== undefined) ? Config.bar.containBar : false)
    readonly property int barSlideAuto: Math.round(animBase * (containBar ? 1.6 : ((hasFrame || Config.showBackground) ? 1.2 : 0.9)))

    // A feature that has modes is ON in any mode but "stock".
    function modeOn(key) {
        return RoadieSettings.mode(key) !== "stock";
    }
    function setModeOn(key, on) {
        RoadieSettings.set(key, on ? "roadie" : "stock");
    }

    readonly property bool enterOn: root.modeOn("enterMode")
    readonly property bool leaveOn: root.modeOn("leaveMode")
    readonly property bool barSlideOn: root.modeOn("barSlideMode")
    readonly property bool frameOn: root.modeOn("frameMode")
    readonly property bool farewellOn: root.modeOn("farewellMode")
    readonly property bool bootLockOn: RoadieSettings.bootLock !== "never"

    readonly property bool anyDuration: root.enterOn || root.leaveOn || RoadieSettings.barSlideMode === "roadie"
        || root.frameOn || root.farewellOn
    readonly property bool anyCustom: root.anyDuration || RoadieSettings.settingsFloat || root.farewellOn

    component SectionTitle: Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        font.weight: Font.DemiBold
        color: Styling.srItem("overprimary")
    }

    component Hint: Text {
        Layout.fillWidth: true
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-2)
        color: Colors.outline
        wrapMode: Text.Wrap
    }

    // A segmented switch with a sliding highlight, looking like the stock
    // SegmentedSwitch. Not that component: its highlight measures the selected
    // button before the buttons exist (nothing upstream uses it, so nobody
    // saw) and sat as a squashed blob until the selection changed once; and it
    // assigns currentIndex on click, which would cut the binding that lets
    // Reset and "Stock everything" move the switches. Here the SELECTED button
    // reports its own geometry, and the index is only ever what the setting is.
    component ModeSwitch: StyledRect {
        id: seg
        property var options: []
        property int currentIndex: 0
        signal picked(int index)

        property real selX: 0
        property real selW: 0
        property bool ready: false
        Component.onCompleted: Qt.callLater(() => seg.ready = true)

        variant: "common"
        radius: Styling.radius(-4)
        enableShadow: false
        implicitWidth: segRow.implicitWidth + 4
        implicitHeight: 32

        StyledRect {
            variant: "focus"
            radius: Styling.radius(-6)
            enableShadow: false
            x: 2 + seg.selX
            y: 2
            width: seg.selW
            height: seg.height - 4
            visible: seg.selW > 0

            Behavior on x {
                enabled: seg.ready && Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                enabled: seg.ready && Config.animDuration > 0
                NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutCubic }
            }
        }

        Row {
            id: segRow
            x: 2
            y: 2
            height: seg.height - 4
            spacing: 2

            Repeater {
                model: seg.options

                Item {
                    id: segButton
                    required property var modelData
                    required property int index
                    readonly property bool selected: seg.currentIndex === index

                    width: segLabel.implicitWidth + 20
                    height: segRow.height

                    Binding {
                        target: seg
                        property: "selX"
                        value: segButton.x
                        when: segButton.selected
                    }
                    Binding {
                        target: seg
                        property: "selW"
                        value: segButton.width
                        when: segButton.selected
                    }

                    Text {
                        id: segLabel
                        anchors.centerIn: parent
                        text: String(segButton.modelData)
                        color: segButton.selected ? Styling.srItem("overprimary") : Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        font.weight: segButton.selected ? Font.DemiBold : Font.Normal
                    }

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: String(segButton.modelData)
                    Accessible.checked: segButton.selected

                    TapHandler {
                        onTapped: seg.picked(segButton.index)
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }

    component ToggleRow: RowLayout {
        id: toggleRow
        property string label: ""
        property string hint: ""
        property bool checked: false
        signal toggled(bool value)

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: toggleRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                wrapMode: Text.Wrap
            }
            Hint {
                visible: toggleRow.hint !== ""
                text: toggleRow.hint
            }
        }

        Switch {
            id: toggleSwitch
            checked: toggleRow.checked
            onToggled: toggleRow.toggled(checked)

            indicator: Rectangle {
                implicitWidth: 40
                implicitHeight: 20
                x: toggleSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                Rectangle {
                    x: toggleSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: toggleSwitch.checked ? Colors.background : Colors.overSurfaceVariant
                    Behavior on x {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutCubic }
                    }
                }
            }
            background: null
        }
    }

    component GroupTitle: Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        color: Colors.outline
    }

    // One of the three groups: what it is for, then its rows.
    component SettingsGroup: ColumnLayout {
        id: group
        property string intro: ""
        default property alias rows: groupRows.data

        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
        Layout.preferredWidth: root.pageWidth
        Layout.maximumWidth: root.pageWidth
        spacing: 8

        Hint {
            visible: group.intro !== ""
            text: group.intro
        }
        ColumnLayout {
            id: groupRows
            Layout.fillWidth: true
            spacing: 10
        }
    }

    // label ................................ [ 650 ] ms     ("auto 480" when derived)
    component DurationRow: RowLayout {
        id: durationRow
        property string label: ""
        property string hint: ""
        property string settingKey: ""
        // > 0: the normal duration is derived, and 0 in the file means "auto".
        property int autoValue: 0

        readonly property int stored: RoadieSettings.ms(durationRow.settingKey)
        readonly property bool isAuto: durationRow.autoValue > 0 && durationRow.stored === 0

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: durationRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                wrapMode: Text.Wrap
            }
            Hint {
                visible: durationRow.hint !== ""
                text: durationRow.hint
            }
        }

        StyledRect {
            variant: durationInput.activeFocus ? "focus" : "common"
            Layout.preferredWidth: 84
            Layout.preferredHeight: 32
            radius: Styling.radius(-2)
            enableShadow: false

            TextInput {
                id: durationInput
                anchors.fill: parent
                anchors.margins: 8
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                selectByMouse: true
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                validator: IntValidator { bottom: 0; top: 10000 }

                readonly property string shown: durationRow.isAuto ? "" : String(durationRow.stored)
                onShownChanged: if (!activeFocus) text = shown
                Component.onCompleted: text = shown

                onEditingFinished: {
                    const t = text.trim();
                    if (t === "") {
                        RoadieSettings.reset(durationRow.settingKey); // cleared: the normal duration
                    } else {
                        const n = parseInt(t, 10);
                        if (!isNaN(n))
                            RoadieSettings.set(durationRow.settingKey, Math.max(0, Math.min(10000, n)));
                    }
                    text = shown;
                }
            }

            Text {
                anchors.centerIn: parent
                visible: durationRow.isAuto && durationInput.text === "" && !durationInput.activeFocus
                text: "auto " + durationRow.autoValue
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
            }
        }

        Text {
            Layout.preferredWidth: 20
            text: "ms"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overSurfaceVariant
        }
    }

    // label
    // hint
    // [ choice | choice | choice ]          (under the text: three choices do
    //                                        not fit beside it in a column)
    component ChoiceRow: ColumnLayout {
        id: choiceRow
        property string label: ""
        property string hint: ""
        property string settingKey: ""
        property var choices: []   // [{ label, value }]

        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: choiceRow.label
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            wrapMode: Text.Wrap
        }
        Hint {
            visible: choiceRow.hint !== ""
            text: choiceRow.hint
        }
        ModeSwitch {
            Layout.topMargin: 2
            options: choiceRow.choices.map(c => c.label)
            currentIndex: Math.max(0, choiceRow.choices.findIndex(c => c.value === RoadieSettings.get(choiceRow.settingKey)))
            onPicked: index => RoadieSettings.set(choiceRow.settingKey, choiceRow.choices[index].value)
        }
    }

    // label ......................................... [ 41 ] %
    component NumberRow: RowLayout {
        id: numberRow
        property string label: ""
        property string hint: ""
        property string settingKey: ""
        property int from: 0
        property int to: 100
        property string unit: ""

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: numberRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                wrapMode: Text.Wrap
            }
            Hint {
                visible: numberRow.hint !== ""
                text: numberRow.hint
            }
        }

        StyledRect {
            variant: numberInput.activeFocus ? "focus" : "common"
            Layout.preferredWidth: 84
            Layout.preferredHeight: 32
            radius: Styling.radius(-2)
            enableShadow: false

            TextInput {
                id: numberInput
                anchors.fill: parent
                anchors.margins: 8
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                selectByMouse: true
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                validator: IntValidator { bottom: numberRow.from; top: numberRow.to }

                readonly property string shown: String(RoadieSettings.get(numberRow.settingKey))
                onShownChanged: if (!activeFocus) text = shown
                Component.onCompleted: text = shown

                onEditingFinished: {
                    const n = parseInt(text.trim(), 10);
                    if (isNaN(n))
                        RoadieSettings.reset(numberRow.settingKey); // cleared: the normal value
                    else
                        RoadieSettings.set(numberRow.settingKey, Math.max(numberRow.from, Math.min(numberRow.to, n)));
                    text = shown;
                }
            }
        }

        Text {
            Layout.preferredWidth: 14
            text: numberRow.unit
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overSurfaceVariant
        }
    }

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            width: mainFlickable.width
            spacing: 10

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.pageWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Roadie"
                    statusText: RoadieSettings.allStock ? "Stock everything" : ""
                    actions: [
                        {
                            icon: Icons.cube,
                            tooltip: "Stock everything: every feature off, plain Ambxst with only Roadie's fixes",
                            onClicked: function () {
                                RoadieSettings.stockAll();
                            }
                        },
                        {
                            icon: Icons.arrowCounterClockwise,
                            tooltip: "Reset everything on this page to Roadie's defaults",
                            onClicked: function () {
                                RoadieSettings.resetAll();
                            }
                        }
                    ]
                }
            }

            ModeSwitch {
                Layout.alignment: Qt.AlignHCenter
                options: root.tabNames
                currentIndex: root.tab
                onPicked: index => RoadieSettings.set("page", index)
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                Layout.preferredWidth: root.pageWidth
                Layout.maximumWidth: root.pageWidth
                spacing: 0

                // ═══ FEATURES ════════════════════════════════════════
                SettingsGroup {
                    visible: root.tab === 0
                    intro: "What Roadie does. Off is what plain Ambxst does there. The fixes (monitor hotplug, fullscreen detection, a bar that never gets stranded) have no switch."

                    GroupTitle { text: "Shell" }
                    ToggleRow {
                        label: "Staged shell start"
                        hint: "The wallpaper fades in, the frame grows in, then bar, notch and dock arrive, at boot and after a reload. Off: everything appears at once."
                        checked: root.enterOn
                        onToggled: value => root.setModeOn("enterMode", value)
                    }
                    ToggleRow {
                        label: "Staged reload"
                        hint: "Bar, notch and dock leave, the frame follows and the wallpaper fades out before the shell restarts. Off: it is restarted with no way out."
                        checked: root.leaveOn
                        onToggled: value => root.setModeOn("leaveMode", value)
                    }
                    ToggleRow {
                        label: "Cover a sudden restart"
                        hint: "A tiny helper shows the wallpaper and frame if the shell is killed without leaving first. Takes effect on the next reload."
                        checked: RoadieSettings.veilEnabled
                        onToggled: value => RoadieSettings.set("veilEnabled", value)
                    }
                    ToggleRow {
                        label: "Lock after boot"
                        hint: "The shell locks once the wallpaper and frame are in, and the bar follows when you unlock."
                        checked: root.bootLockOn
                        onToggled: value => RoadieSettings.set("bootLock", value ? "auto" : "never")
                    }
                    ToggleRow {
                        label: "Farewell on reboot and power off"
                        hint: "The notch grows into the whole screen and a line from a film or show fades in before the command runs."
                        checked: root.farewellOn
                        onToggled: value => root.setModeOn("farewellMode", value)
                    }

                    GroupTitle { text: "Screens" }
                    ToggleRow {
                        label: "Bar follows the focused screen"
                        hint: "A pinned bar shows only on the screen that has focus and slides across when focus moves. Off: every screen keeps its bar."
                        checked: RoadieSettings.followFocus
                        onToggled: value => RoadieSettings.set("followFocus", value)
                    }
                    ToggleRow {
                        label: "Notifications follow the focused screen"
                        hint: "One screen pops a notification: the focused one, or a free one if a window is fullscreen there. Off: every screen pops it."
                        checked: RoadieSettings.notifyFollowFocus
                        onToggled: value => RoadieSettings.set("notifyFollowFocus", value)
                    }
                    ToggleRow {
                        label: "Staged bar slide"
                        hint: "The bar leaves and returns with the windows moving in step: focus changing screens, a fullscreen window, an auto-hide bar. Off: Ambxst's quick hide and reveal."
                        checked: root.barSlideOn
                        onToggled: value => root.setModeOn("barSlideMode", value)
                    }
                    ToggleRow {
                        label: "Animated frame around fullscreen windows"
                        hint: "The frame collapses when a window goes fullscreen and grows back when it leaves. Off: it drops and returns at once."
                        checked: root.frameOn
                        onToggled: value => root.setModeOn("frameMode", value)
                    }
                    ToggleRow {
                        label: "Notch hangs off the edge over fullscreen"
                        hint: "Over a fullscreen window a peeking notch sits on the screen edge with square corners, and an opened one brings the frame back with the bar. Off: the frame's strip returns under it."
                        checked: root.modeOn("notchCoverMode")
                        onToggled: value => root.setModeOn("notchCoverMode", value)
                    }
                    ToggleRow {
                        label: "Remember the monitors' brightness channels"
                        hint: "Skips the monitor query Ambxst runs at every start, which freezes the desktop for about a second on some GPUs."
                        checked: RoadieSettings.ddcCache
                        onToggled: value => RoadieSettings.set("ddcCache", value)
                    }

                    GroupTitle { text: "Bar and notch" }
                    ToggleRow {
                        label: "Bluetooth in the bar"
                        hint: "An indicator with a panel for power, scanning and your devices, and a battery readout. Off also brings blueman's tray icon back."
                        checked: RoadieSettings.bluetoothWidget
                        onToggled: value => RoadieSettings.set("bluetoothWidget", value)
                    }
                    ToggleRow {
                        label: "Popouts grow out of the frame"
                        hint: "With contain bar on, the clock, controls, battery, layout and hidden tray icons popouts and the tray icons' menus are part of the frame. Off: floating pills."
                        checked: RoadieSettings.framePopouts
                        onToggled: value => RoadieSettings.set("framePopouts", value)
                    }
                    ToggleRow {
                        label: "Audio routing tab in the dashboard"
                        hint: "Every program playing or recording audio, where it goes, its volume, and a dropdown to move it. Takes effect on the next reload."
                        checked: RoadieSettings.audioTab
                        onToggled: value => RoadieSettings.set("audioTab", value)
                    }
                    ToggleRow {
                        label: "Ethernet switch in the notch"
                        hint: "While a cable is plugged in, the quick controls get an Ethernet switch to the left of the Wi-Fi one. It leaves with the cable."
                        checked: RoadieSettings.ethernetButton
                        onToggled: value => RoadieSettings.set("ethernetButton", value)
                    }

                    GroupTitle { text: "Settings and mods" }
                    ToggleRow {
                        label: "Settings opens as a floating window"
                        hint: "Centred and sized to the screen, never a tile first. Applies the next time Settings is opened."
                        checked: RoadieSettings.settingsFloat
                        onToggled: value => RoadieSettings.set("settingsFloat", value)
                    }
                    ToggleRow {
                        label: "Check for mod updates automatically"
                        hint: "Shortly after the shell starts and every few hours, with a notification when any are found. The Check for updates button in Settings > Mods is always there."
                        checked: RoadieSettings.modAutoCheck
                        onToggled: value => RoadieSettings.set("modAutoCheck", value)
                    }

                    Hint {
                        Layout.topMargin: 6
                        text: "Icon colours: True Matugen Icons and True Monochrome are under Settings > Theme, with Tint Icons. Claude Code in the AI sidebar is under Settings > AI."
                    }
                }

                // ═══ BEHAVIOURS ══════════════════════════════════════
                SettingsGroup {
                    visible: root.tab === 1
                    intro: "How the features that are switched on behave."

                    ChoiceRow {
                        visible: root.barSlideOn
                        label: "Bar slide"
                        hint: "Animated slides the bar with the windows. Immediate: the bar and its space simply come and go."
                        settingKey: "barSlideMode"
                        choices: [{ label: "Animated", value: "roadie" }, { label: "Immediate", value: "immediate" }]
                    }
                    ChoiceRow {
                        visible: root.farewellOn
                        label: "Farewell"
                        hint: "Animated grows the notch and fades the quote in. Immediate shows the quote with no movement."
                        settingKey: "farewellMode"
                        choices: [{ label: "Animated", value: "roadie" }, { label: "Immediate", value: "immediate" }]
                    }
                    ToggleRow {
                        visible: root.farewellOn
                        label: "Show where the quote is from"
                        checked: RoadieSettings.farewellSource
                        onToggled: value => RoadieSettings.set("farewellSource", value)
                    }
                    ChoiceRow {
                        visible: root.bootLockOn
                        label: "Lock after boot"
                        hint: "Auto skips the lock if you logged in through a greeter (SDDM, GDM, LightDM, greetd, ly...) or an external locker is already up."
                        settingKey: "bootLock"
                        choices: [{ label: "Auto", value: "auto" }, { label: "Always", value: "always" }]
                    }
                    ChoiceRow {
                        label: "Dim the screens when idle"
                        hint: "Ambxst lowers the brightness after a while without input. Laptops only keeps that where there is a battery; Never leaves the screens as you set them. Locking, screen off and suspend are not affected."
                        settingKey: "idleDim"
                        choices: [{ label: "As stock", value: "always" }, { label: "Laptops only", value: "battery" }, { label: "Never", value: "never" }]
                    }
                    ChoiceRow {
                        label: "Volume and brightness pop-ups"
                        hint: "Quiet hides the ones the shell makes by itself while reading its initial state after a start."
                        settingKey: "osd"
                        choices: [{ label: "Quiet at start", value: "quiet" }, { label: "As stock", value: "stock" }, { label: "Off", value: "off" }]
                    }
                    ToggleRow {
                        visible: RoadieSettings.modAutoCheck
                        label: "Install mod updates automatically"
                        hint: "What an automatic check finds is installed right away, then a notification asks you to restart. Updates that need a newer Ambxst always wait for you."
                        checked: RoadieSettings.modAutoInstall
                        onToggled: value => RoadieSettings.set("modAutoInstall", value)
                    }
                    NumberRow {
                        visible: RoadieSettings.modAutoCheck
                        label: "Hours between automatic checks"
                        settingKey: "modCheckHours"
                        from: 1
                        to: 168
                        unit: "h"
                    }
                }

                // ═══ CUSTOMIZATION ═══════════════════════════════════
                SettingsGroup {
                    visible: root.tab === 2
                    intro: root.anyCustom ? "Durations, sizes and quotes of the features that are switched on."
                        : "Nothing to adjust: the features these settings belong to are switched off."

                    GroupTitle {
                        visible: root.anyDuration
                        text: "Animation durations"
                    }
                    Hint {
                        visible: root.anyDuration
                        text: "Clear a field for the normal duration. Auto follows Ambxst's animation speed."
                    }
                    DurationRow {
                        visible: root.enterOn
                        label: "Shell start"
                        hint: "The frame takes this long; wallpaper and bar are paced from it."
                        settingKey: "enterDuration"
                    }
                    DurationRow {
                        visible: root.leaveOn
                        label: "Reload, the way out"
                        settingKey: "leaveDuration"
                    }
                    DurationRow {
                        visible: RoadieSettings.barSlideMode === "roadie"
                        label: "Bar slide"
                        hint: "Auto also follows how much is moving: contained in the frame, a frame or bar background, pills alone."
                        settingKey: "barSlideDuration"
                        autoValue: root.barSlideAuto
                    }
                    DurationRow {
                        visible: root.frameOn
                        label: "Frame around a fullscreen window"
                        settingKey: "frameDuration"
                        autoValue: Math.max(1, root.animBase)
                    }
                    DurationRow {
                        visible: RoadieSettings.farewellMode === "roadie"
                        label: "Farewell, filling the screen"
                        settingKey: "farewellDuration"
                    }
                    DurationRow {
                        visible: root.farewellOn
                        label: "Farewell, reading time"
                        hint: "How long the quote stays up before the command runs, on top of 40 ms per character."
                        settingKey: "farewellHold"
                    }

                    GroupTitle {
                        visible: RoadieSettings.settingsFloat
                        text: "Settings window"
                    }
                    NumberRow {
                        visible: RoadieSettings.settingsFloat
                        label: "Width"
                        hint: "Percent of the screen. Never below 900 px or above 92%."
                        settingKey: "settingsFloatWidth"
                        from: 20
                        to: 100
                        unit: "%"
                    }
                    NumberRow {
                        visible: RoadieSettings.settingsFloat
                        label: "Height"
                        hint: "Percent of the screen. Never below 650 px or above 92%."
                        settingKey: "settingsFloatHeight"
                        from: 20
                        to: 100
                        unit: "%"
                    }

                    // ─── farewell quotes ─────────────────────────────
                    Loader {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        active: root.farewellOn
                        visible: active
                        sourceComponent: RoadieQuotesEditor {}
                    }
                }
            }

            Item { Layout.preferredHeight: 12 }
        }
    }
}
