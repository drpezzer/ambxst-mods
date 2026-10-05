pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Ambxst Roadie (drpezzer.roadie): the Claude Code card of Settings > AI (AiPanel), above
// the providers that take an API key.
//
// One switch: with it on, the Claude Code CLI installed on this machine is a
// provider of the AI sidebar, under its own login, and the sidebar moves to
// it. The API providers below keep working and stay in the sidebar's model
// list. The rest of the card (what Claude Code may do, where it works) only
// shows while the switch is on. Everything is kept in roadie.json
// (RoadieSettings) and applies to the next message sent.
StyledRect {
    id: card

    variant: "surface"
    radius: Styling.radius(8)
    implicitHeight: cardColumn.implicitHeight + 32

    readonly property bool on: RoadieSettings.claudeCode
    readonly property var levels: [
        {
            value: "chat",
            label: "Chat only",
            hint: "Conversation and nothing else: Claude Code cannot look at or touch anything on this machine."
        },
        {
            value: "read",
            label: "Read only",
            hint: "Reads files, runs commands that only look, and searches the web. It changes nothing."
        },
        {
            value: "edit",
            label: "Edit files",
            hint: "Also creates and edits files in the working folder."
        },
        {
            value: "auto",
            label: "Auto",
            hint: "Claude Code's auto mode: it acts by itself, and its safety check refuses what looks risky. On a model without auto mode (Haiku) this is Read only."
        }
    ]
    readonly property int levelIndex: Math.max(0, card.levels.findIndex(l => l.value === RoadieSettings.claudeCodeAccess))

    Component.onCompleted: RoadieClaudeCode.probe()

    component CardLabel: Text {
        Layout.fillWidth: true
        font.family: Config.theme.font
        font.pixelSize: 14
        color: Colors.overSurface
        wrapMode: Text.Wrap
    }

    component CardHint: Text {
        Layout.fillWidth: true
        font.family: Config.theme.font
        font.pixelSize: 12
        color: Colors.outline
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        id: cardColumn
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Claude Code"
                font.family: Config.theme.font
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
            }
            Text {
                visible: RoadieClaudeCode.probed
                text: RoadieClaudeCode.found ? ("Installed" + (RoadieClaudeCode.version ? " · " + RoadieClaudeCode.version : "")) : "Not installed"
                font.family: Config.theme.font
                font.pixelSize: 12
                color: RoadieClaudeCode.found ? Colors.success : Colors.outline
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                CardLabel {
                    text: "Use Claude Code in the sidebar"
                }
                CardHint {
                    text: "Chat with the Claude Code installed on this machine, under its own login. No API key. The providers below keep working, and stay in the sidebar's model list."
                }
            }

            Switch {
                id: useSwitch
                checked: card.on
                onToggled: RoadieClaudeCode.setEnabled(checked)

                indicator: Rectangle {
                    implicitWidth: 40
                    implicitHeight: 20
                    x: useSwitch.leftPadding
                    y: parent.height / 2 - height / 2
                    radius: height / 2
                    color: useSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                    border.color: useSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                    Rectangle {
                        x: useSwitch.checked ? parent.width - width - 2 : 2
                        y: 2
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: useSwitch.checked ? Colors.background : Colors.overSurfaceVariant
                        Behavior on x {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                background: null
            }
        }

        CardHint {
            visible: card.on && RoadieClaudeCode.probed && !RoadieClaudeCode.found
            color: Colors.error
            text: "The claude command was not found. Install Claude Code, then run claude once in a terminal to log in."
        }

        // ─── what it may do ──────────────────────────────────────────
        ColumnLayout {
            visible: card.on
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                height: 1
                color: Colors.outline
                opacity: 0.2
            }

            CardLabel {
                text: "What it may do"
            }

            // Ambxst's SegmentedSwitch measures its highlight before its
            // buttons exist; this one follows the selected button.
            StyledRect {
                id: seg
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
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on width {
                        enabled: seg.ready && Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Row {
                    id: segRow
                    x: 2
                    y: 2
                    height: seg.height - 4
                    spacing: 2

                    Repeater {
                        model: card.levels

                        Item {
                            id: segButton
                            required property var modelData
                            required property int index
                            readonly property bool selected: card.levelIndex === index

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
                                text: segButton.modelData.label
                                color: segButton.selected ? Styling.srItem("overprimary") : Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 14
                                font.weight: segButton.selected ? Font.DemiBold : Font.Normal
                            }

                            Accessible.role: Accessible.RadioButton
                            Accessible.name: segButton.modelData.label
                            Accessible.checked: segButton.selected

                            TapHandler {
                                onTapped: RoadieSettings.set("claudeCodeAccess", segButton.modelData.value)
                            }
                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }
            }

            CardHint {
                text: card.levels[card.levelIndex].hint + " Nothing can ask for your permission from the sidebar: what a level does not allow is refused."
            }
        }

        // ─── where it works ──────────────────────────────────────────
        ColumnLayout {
            visible: card.on
            Layout.fillWidth: true
            spacing: 6

            CardLabel {
                text: "Working folder"
            }

            TextField {
                id: folderInput
                Layout.fillWidth: true
                placeholderText: "Home folder"
                font.family: Config.theme.font
                color: Colors.overSurface
                padding: 6

                readonly property string shown: RoadieSettings.claudeCodeDir
                onShownChanged: if (!activeFocus) text = shown
                Component.onCompleted: text = shown
                onEditingFinished: RoadieSettings.set("claudeCodeDir", text.trim())

                background: StyledRect {
                    variant: "internalbg"
                    radius: Styling.radius(4)
                    border.width: folderInput.activeFocus ? 2 : 0
                    border.color: Styling.srItem("primary")
                    anchors.fill: parent
                    anchors.leftMargin: -parent.padding
                    anchors.rightMargin: -parent.padding
                    anchors.topMargin: -parent.padding
                    anchors.bottomMargin: -parent.padding
                }
            }

            CardHint {
                text: "Where Claude Code starts, as if you had run it in a terminal there: that folder's CLAUDE.md and memory apply, and the chats show up in claude --resume. Empty is your home folder."
            }
        }
    }
}
