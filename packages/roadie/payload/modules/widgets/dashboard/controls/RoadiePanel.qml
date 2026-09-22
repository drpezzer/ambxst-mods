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
// Everything Roadie changes has a mode: Roadie (its own animation, with a
// duration you can type), Stock (what plain Ambxst does there) and, where that
// is a different thing, Immediate. Where the normal duration is derived from
// Ambxst's animation speed the field shows it as "auto"; clearing the field
// goes back to that. "Stock everything" in the title bar is plain Ambxst with
// only the fixes left.
Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    property string currentSection: ""

    // What BarContent derives when the bar slide is left on automatic.
    readonly property int animBase: Config.animDuration !== undefined ? Config.animDuration : 300
    readonly property bool hasFrame: (Config.bar && Config.bar.frameEnabled !== undefined) ? Config.bar.frameEnabled : false
    readonly property bool containBar: hasFrame && ((Config.bar && Config.bar.containBar !== undefined) ? Config.bar.containBar : false)
    readonly property int barSlideAuto: Math.round(animBase * (containBar ? 1.6 : ((hasFrame || Config.showBackground) ? 1.2 : 0.9)))

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

    // label ........................ [ Roadie | Stock | Immediate ]
    //                                         Duration [ 650 ] ms
    component ModeRow: ColumnLayout {
        id: modeRow
        property string label: ""
        property string hint: ""
        property string stockHint: ""
        // Settings keys. modeKey "" = a plain duration; durationKey "" = a mode only.
        property string modeKey: ""
        property string durationKey: ""
        // > 0: the normal duration is derived, and 0 in the file means "auto".
        property int autoValue: 0

        readonly property var modes: modeKey !== "" ? (RoadieSettings.modeChoices[modeKey] || []) : []
        readonly property string mode: modeKey !== "" ? RoadieSettings.mode(modeKey) : "roadie"
        readonly property int stored: durationKey !== "" ? RoadieSettings.ms(durationKey) : 0
        readonly property bool isAuto: autoValue > 0 && stored === 0
        function modeLabel(m) {
            return m === "roadie" ? "Roadie" : (m === "stock" ? "Stock" : "Immediate");
        }

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: modeRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overBackground
                wrapMode: Text.Wrap
            }

            ModeSwitch {
                visible: modeRow.modeKey !== ""
                options: modeRow.modes.map(m => modeRow.modeLabel(m))
                currentIndex: Math.max(0, modeRow.modes.indexOf(modeRow.mode))
                onPicked: index => RoadieSettings.set(modeRow.modeKey, modeRow.modes[index])
            }
        }

        RowLayout {
            visible: modeRow.durationKey !== "" && modeRow.mode === "roadie"
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: modeRow.modeKey !== "" ? "Duration" : ""
                horizontalAlignment: Text.AlignRight
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
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

                    readonly property string shown: modeRow.isAuto ? "" : String(modeRow.stored)
                    onShownChanged: if (!activeFocus) text = shown
                    Component.onCompleted: text = shown

                    onEditingFinished: {
                        const t = text.trim();
                        if (t === "") {
                            RoadieSettings.reset(modeRow.durationKey); // cleared: the normal duration
                        } else {
                            const n = parseInt(t, 10);
                            if (!isNaN(n))
                                RoadieSettings.set(modeRow.durationKey, Math.max(0, Math.min(10000, n)));
                        }
                        text = shown;
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: modeRow.isAuto && durationInput.text === "" && !durationInput.activeFocus
                    text: "auto " + modeRow.autoValue
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.outline
                }
            }

            Text {
                text: "ms"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurfaceVariant
            }
        }

        Hint {
            visible: text !== ""
            text: modeRow.mode === "stock" && modeRow.stockHint !== "" ? ("Stock: " + modeRow.stockHint) : modeRow.hint
        }
    }

    component ChoiceRow: RowLayout {
        id: choiceRow
        property string label: ""
        property string hint: ""
        property string settingKey: ""
        property var choices: []   // [{ label, value }]

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
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
        }

        ModeSwitch {
            options: choiceRow.choices.map(c => c.label)
            currentIndex: Math.max(0, choiceRow.choices.findIndex(c => c.value === RoadieSettings.get(choiceRow.settingKey)))
            onPicked: index => RoadieSettings.set(choiceRow.settingKey, choiceRow.choices[index].value)
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
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Roadie"
                    statusText: RoadieSettings.allStock ? "Stock everything" : ""
                    actions: [
                        {
                            icon: Icons.cube,
                            tooltip: "Stock everything: plain Ambxst animations and behaviour, only Roadie's fixes stay",
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

            ColumnLayout {
                Layout.preferredWidth: root.contentWidth
                Layout.maximumWidth: root.contentWidth
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                // ─── animations ──────────────────────────────────────
                SectionTitle { text: "Animations" }
                Hint {
                    text: "Roadie is this mod's animation, for the duration beside it (clear the field for the normal one). Stock is what plain Ambxst does. Immediate: it simply happens."
                }

                ModeRow {
                    label: "Shell start"
                    hint: "Wallpaper fades in, the frame grows in, then bar, notch and dock arrive (boot and reload). The frame takes this long; the others are paced from it."
                    stockHint: "everything appears at once."
                    modeKey: "enterMode"
                    durationKey: "enterDuration"
                }
                ModeRow {
                    label: "Shell reload, the way out"
                    hint: "Bar, notch and dock leave, the frame follows, the wallpaper fades to the background colour, then the shell restarts."
                    stockHint: "the shell is restarted with no way out."
                    modeKey: "leaveMode"
                    durationKey: "leaveDuration"
                }
                ModeRow {
                    label: "Bar slide"
                    hint: "The bar leaving and returning with the windows: focus moving between screens, a fullscreen window, an auto-hide bar. Automatic follows Ambxst's animation speed and how much is moving (contained in the frame, a frame or bar background, pills alone)."
                    stockHint: "Ambxst's quick hide and reveal, not staged and not synced with the windows. The bar's space is still released and taken back."
                    modeKey: "barSlideMode"
                    durationKey: "barSlideDuration"
                    autoValue: root.barSlideAuto
                }
                ModeRow {
                    label: "Frame around a fullscreen window"
                    hint: "The frame collapsing when a window goes fullscreen and growing back when it leaves. Automatic is Ambxst's animation speed."
                    stockHint: "it drops and returns at once."
                    modeKey: "frameMode"
                    durationKey: "frameDuration"
                    autoValue: Math.max(1, root.animBase)
                }
                ModeRow {
                    label: "Notch over a fullscreen window"
                    hint: "A peeking notch hangs off the screen edge with square corners; an opened one brings the frame back with the bar."
                    stockHint: "the frame's strip returns under the notch and all four corners round."
                    modeKey: "notchCoverMode"
                }
                ModeRow {
                    label: "Farewell on reboot and power off"
                    hint: "The notch grows into the whole screen and a line from a film or show fades in before the command runs. The duration is the notch filling the screen."
                    stockHint: "no farewell, the command runs at once."
                    modeKey: "farewellMode"
                    durationKey: "farewellDuration"
                }
                ModeRow {
                    visible: RoadieSettings.farewellMode !== "stock"
                    label: "Farewell, reading time"
                    hint: "How long the quote stays up before the command runs, on top of 40 ms per character."
                    durationKey: "farewellHold"
                }

                Separator { Layout.fillWidth: true; Layout.topMargin: 6 }

                // ─── behaviour ───────────────────────────────────────
                SectionTitle { text: "Behaviour" }

                ToggleRow {
                    label: "Bar follows the focused screen"
                    hint: "A pinned bar shows only on the screen that has focus and slides across when focus moves. Off (stock): every screen keeps its bar."
                    checked: RoadieSettings.followFocus
                    onToggled: value => RoadieSettings.set("followFocus", value)
                }
                ToggleRow {
                    label: "Notifications follow the focused screen"
                    hint: "The notch pops a notification on the screen that has focus only. If a window is fullscreen there and another screen is free, it goes to that screen instead; with one screen it stays where it is (the dashboard's bell silences them). Off (stock): every screen pops it."
                    checked: RoadieSettings.notifyFollowFocus
                    onToggled: value => RoadieSettings.set("notifyFollowFocus", value)
                }
                ToggleRow {
                    label: "Show where the quote is from"
                    checked: RoadieSettings.farewellSource
                    onToggled: value => RoadieSettings.set("farewellSource", value)
                }
                ChoiceRow {
                    label: "Lock after boot"
                    hint: "Auto locks once the wallpaper and frame are in, unless you logged in through a greeter (SDDM, GDM, LightDM, greetd, ly...) or an external locker is already up. Never is stock."
                    settingKey: "bootLock"
                    choices: [{ label: "Auto", value: "auto" }, { label: "Always", value: "always" }, { label: "Never", value: "never" }]
                }
                ChoiceRow {
                    label: "Volume and brightness pop-ups"
                    hint: "Quiet hides the ones the shell makes by itself while reading its initial state after a start."
                    settingKey: "osd"
                    choices: [{ label: "Quiet at start", value: "quiet" }, { label: "As stock", value: "stock" }, { label: "Off", value: "off" }]
                }
                ToggleRow {
                    label: "Remember the monitors' brightness channels"
                    hint: "Ambxst asks every monitor for its DDC channel and brightness at each start, which freezes the whole desktop for about a second on some GPUs. On: a reload reuses what this session already learned, and the first start after a boot reuses the channels if the same monitors sit on the same adapters, then checks the brightness a few seconds after the entrance (a changed monitor set or a wake from suspend asks again). Off is stock."
                    checked: RoadieSettings.ddcCache
                    onToggled: value => RoadieSettings.set("ddcCache", value)
                }
                ToggleRow {
                    label: "Cover a cold kill with the veil helper"
                    hint: "A tiny detached helper that shows the wallpaper and frame and plays the way out itself if the shell is killed without leaving first. Off is stock. Takes effect on the next reload."
                    checked: RoadieSettings.veilEnabled
                    onToggled: value => RoadieSettings.set("veilEnabled", value)
                }

                // ─── farewell quotes ─────────────────────────────────
                RoadieQuotesEditor {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                }

                Item { Layout.preferredHeight: 12 }
            }
        }
    }
}
