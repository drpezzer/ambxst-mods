pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Ambxst Roadie (drpezzer.roadie): the farewell's quote editor, shown under
// the mod's settings in Settings > Mods while Roadie is selected. Everything
// here reads and writes ~/.config/ambxst/roadie-quotes.json through
// ShellFarewell, the same file people can edit by hand.
ColumnLayout {
    id: editor

    Layout.fillWidth: true
    spacing: 6

    readonly property var doc: ShellFarewell.userDoc()
    property string builtinOpen: ""   // kind whose built-in list is unfolded

    function kindTitle(kind) {
        return kind === "reboot" ? "Reboot · back in a second" : "Shutdown · a goodbye";
    }

    // The same button ModsPanel uses (its ActionButton is a private inline
    // component there, so it is repeated here rather than imported).
    component ActionButton: Button {
        id: action
        property bool primary: false
        property bool destructive: false

        implicitHeight: 34
        leftPadding: 14
        rightPadding: 14
        enabled: !ModsService.busy
        opacity: enabled ? 1 : 0.45

        readonly property bool engaged: hovered || down || activeFocus
        readonly property string surface: action.primary
            ? (action.engaged ? "primaryfocus" : "primary")
            : (action.engaged ? (action.destructive ? "error" : "secondary") : "focus")

        background: StyledRect {
            variant: action.surface
            radius: Styling.radius(-2)
            enableShadow: false
        }

        contentItem: Text {
            text: action.text
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            font.weight: action.primary ? Font.DemiBold : Font.Medium
            color: action.primary || action.engaged ? Styling.srItem(action.surface)
                : action.destructive ? Colors.error
                : Colors.overBackground
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component Field: TextField {
        id: field
        implicitHeight: 34
        color: Colors.overBackground
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        selectByMouse: true
        placeholderTextColor: Colors.outline
        background: StyledRect {
            variant: field.activeFocus ? "focus" : "common"
            radius: Styling.radius(-2)
            enableShadow: false
        }
    }

    Separator { Layout.fillWidth: true }

    Text {
        text: "Farewell quotes"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        font.weight: Font.DemiBold
        color: Colors.overBackground
    }

    Text {
        Layout.fillWidth: true
        text: "Lines shown while the machine shuts down or reboots. Yours are added to the built-in ones (or stand in for them). A line that does not end in a full stop gets one. Where it is from is optional and only shows with \"Show where the quote is from\" on. Kept in ~/.config/ambxst/roadie-quotes.json."
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-2)
        color: Colors.outline
        wrapMode: Text.Wrap
    }

    Repeater {
        model: ["shutdown", "reboot"]

        delegate: ColumnLayout {
            id: section
            required property string modelData
            readonly property string kind: modelData
            readonly property var mine: editor.doc[kind] || []
            readonly property var builtin: ShellFarewell.builtin[kind] || []
            readonly property var hidden: editor.doc.hidden || []
            readonly property bool unfolded: editor.builtinOpen === kind

            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4

            Text {
                text: editor.kindTitle(section.kind)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: Colors.overBackground
            }

            Text {
                visible: section.mine.length === 0
                text: "No lines of your own yet."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
            }

            Repeater {
                model: section.mine

                delegate: RowLayout {
                    id: mineRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: mineRow.modelData.text + (mineRow.modelData.source ? "  —  " + mineRow.modelData.source : "")
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        wrapMode: Text.Wrap
                    }

                    ActionButton {
                        text: "Remove"
                        destructive: true
                        onClicked: ShellFarewell.removeUserQuote(section.kind, mineRow.index)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Field {
                    id: lineInput
                    Layout.fillWidth: true
                    placeholderText: section.kind === "reboot" ? "A line for the way back, e.g. I'll be back." : "A goodbye, e.g. See you in another life, brother."
                    onAccepted: addButton.clicked()
                }

                Field {
                    id: sourceInput
                    Layout.preferredWidth: 200
                    placeholderText: "From (optional)"
                    onAccepted: addButton.clicked()
                }

                ActionButton {
                    id: addButton
                    text: "Add"
                    primary: true
                    enabled: !ModsService.busy && lineInput.text.trim().length > 0
                    onClicked: {
                        if (ShellFarewell.addUserQuote(section.kind, lineInput.text, sourceInput.text)) {
                            lineInput.text = "";
                            sourceInput.text = "";
                            lineInput.forceActiveFocus();
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: {
                        const total = section.builtin.length;
                        const off = section.builtin.filter(q => section.hidden.indexOf(q.text) !== -1).length;
                        return "Built-in lines: " + total + (off > 0 ? " (" + off + " hidden)" : "");
                    }
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.outline
                }

                ActionButton {
                    text: section.unfolded ? "Hide list" : "Show list"
                    onClicked: editor.builtinOpen = section.unfolded ? "" : section.kind
                }
            }

            ColumnLayout {
                visible: section.unfolded
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 2

                Repeater {
                    model: section.unfolded ? section.builtin : []

                    delegate: RowLayout {
                        id: builtinRow
                        required property var modelData
                        readonly property bool off: section.hidden.indexOf(modelData.text) !== -1
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: builtinRow.modelData.text + "  —  " + builtinRow.modelData.source
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.strikeout: builtinRow.off
                            color: builtinRow.off ? Colors.outline : Colors.overBackground
                            wrapMode: Text.Wrap
                        }

                        ActionButton {
                            text: builtinRow.off ? "Show" : "Hide"
                            implicitHeight: 28
                            onClicked: ShellFarewell.setHidden(builtinRow.modelData.text, !builtinRow.off)
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: "Use only your own lines"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: Colors.overBackground
            }

            Text {
                Layout.fillWidth: true
                text: "On: the built-in lines are not used at all (a kind with no lines of your own keeps the built-in ones). Off: yours are added to them."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
                wrapMode: Text.Wrap
            }
        }

        ActionButton {
            text: editor.doc.replace ? "On" : "Off"
            primary: editor.doc.replace
            onClicked: ShellFarewell.setReplace(!editor.doc.replace)
        }
    }
}
