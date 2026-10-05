pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Ambxst Roadie (drpezzer.roadie): the box under a reply of Claude Code that
// wanted a command run as root. See RoadieSudo for what the buttons do.
//
//   Run this sudo command?            Running as root...          Ran as root
//   sudo pacman -S --noconfirm tree   (the output, as it arrives) (the output)
//                      [ No ] [ Yes ]                    [ Stop ]
//
// Yes turns the two buttons into a field for the password (unless sudo needs
// none): Enter runs the command, Escape goes back to the buttons.
ColumnLayout {
    id: box

    required property var request       // the message's `sudo`
    required property int messageIndex
    required property bool last         // nothing has been said since

    // The command is running, and it is this one.
    readonly property bool live: RoadieSudo.running && RoadieSudo.chatId === Ai.currentChatId && RoadieSudo.index === box.messageIndex
    // "running" in the chat with nothing running: the shell was restarted
    // under it. A question the user answered by typing something else was
    // answered No.
    readonly property bool asking: !!RoadieSudo.asking && RoadieSudo.asking.chatId === Ai.currentChatId && RoadieSudo.asking.index === box.messageIndex
    readonly property string phase: {
        if (box.live)
            return "running";
        if (box.asking && box.request.state === "pending")
            return "asking";
        if (box.request.state === "running")
            return "lost";
        if (box.request.state === "pending" && !box.last)
            return "declined";
        return box.request.state || "pending";
    }
    readonly property string shown: box.live ? RoadieSudo.output : (box.request.output || "")

    spacing: 8

    // The bubble is as wide as what it holds asks for; this asks for all of it.
    Item {
        implicitWidth: 2000
        implicitHeight: 0
        Layout.fillWidth: true
    }

    Text {
        Layout.fillWidth: true
        text: {
            switch (box.phase) {
            case "pending":
            case "asking":
                return "Run this sudo command?";
            case "running":
                return "Running as root…";
            case "done":
                return box.request.exitCode === 0 ? "Ran as root" : "Ran as root, exit status " + box.request.exitCode;
            case "cancelled":
                return "Stopped";
            case "lost":
                return "Interrupted: the shell restarted while it ran";
            default:
                return "Not run";
            }
        }
        color: {
            switch (box.phase) {
            case "pending":
            case "asking":
            case "running":
                return Styling.srItem("overprimary");
            case "done":
                return box.request.exitCode === 0 ? Colors.success : Colors.error;
            default:
                return Colors.outline;
            }
        }
        font.family: Config.theme.font
        font.weight: Font.Bold
        font.pixelSize: 13
        wrapMode: Text.Wrap
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: commandText.implicitHeight
        variant: "surface"
        color: Colors.surface
        radius: Styling.radius(4)

        TextEdit {
            id: commandText
            padding: 8
            width: parent.width
            text: box.request.command || ""
            font.family: "Monospace"
            font.pixelSize: 13
            color: Colors.overSurface
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WrapAnywhere
        }
    }

    // What it printed, the end of it in view.
    StyledRect {
        Layout.fillWidth: true
        visible: box.shown.trim() !== "" && box.phase !== "pending" && box.phase !== "asking" && box.phase !== "declined"
        implicitHeight: Math.min(outputText.implicitHeight, 180)
        variant: "surface"
        color: Colors.surface
        radius: Styling.radius(4)
        clip: true

        Flickable {
            id: outputView
            anchors.fill: parent
            contentWidth: width
            contentHeight: outputText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

            TextEdit {
                id: outputText
                padding: 8
                width: outputView.width
                text: box.shown.replace(/\n+$/, "")
                font.family: "Monospace"
                font.pixelSize: 12
                color: Colors.overSurfaceVariant
                readOnly: true
                selectByMouse: true
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    component Choice: Button {
        id: choice
        property string plate: "primary"
        property color ink: Colors.overPrimary
        flat: true
        leftPadding: 14
        rightPadding: 14

        background: StyledRect {
            variant: choice.plate
            opacity: choice.hovered ? 1 : 0.8
            radius: Styling.radius(4)
        }
        contentItem: Text {
            text: choice.text
            color: choice.ink
            font.family: Config.theme.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        visible: box.phase === "pending"
        Layout.alignment: Qt.AlignRight
        spacing: 8

        Choice {
            text: "No"
            plate: "error"
            ink: Colors.overError
            onClicked: RoadieSudo.decline(box.messageIndex)
        }
        Choice {
            text: "Yes"
            enabled: !RoadieSudo.running
            onClicked: RoadieSudo.approve(box.messageIndex)
        }
    }

    // ─── the password, in place of the two buttons ───────────────────
    ColumnLayout {
        visible: box.phase === "asking"
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: "Your password, then Enter"
                echoMode: TextInput.Password
                font.family: Config.theme.font
                color: Colors.overSurface
                padding: 6
                leftPadding: 10
                rightPadding: 10

                // The box is built again whenever the chat changes: take the
                // keyboard each time the field is the thing on show.
                onVisibleChanged: if (visible) forceActiveFocus()
                Component.onCompleted: if (visible) forceActiveFocus()

                onAccepted: {
                    const typed = text;
                    text = "";
                    RoadieSudo.submit(typed);
                }
                Keys.onEscapePressed: {
                    text = "";
                    RoadieSudo.back();
                }

                background: StyledRect {
                    variant: "internalbg"
                    radius: Styling.radius(4)
                    border.width: passwordField.activeFocus ? 2 : 0
                    border.color: Styling.srItem("overprimary")
                }
            }

            Choice {
                text: "Back"
                plate: "common"
                ink: Colors.overBackground
                onClicked: {
                    passwordField.text = "";
                    RoadieSudo.back();
                }
            }
            Choice {
                text: "Run"
                enabled: passwordField.text !== ""
                onClicked: passwordField.accepted()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: RoadieSudo.problem !== ""
            text: RoadieSudo.problem
            color: Colors.error
            font.family: Config.theme.font
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    RowLayout {
        visible: box.phase === "running"
        Layout.alignment: Qt.AlignRight

        Choice {
            text: "Stop"
            plate: "error"
            ink: Colors.overError
            onClicked: RoadieSudo.stop()
        }
    }

    Text {
        Layout.fillWidth: true
        visible: box.phase === "declined" && box.last
        text: "Say what to do instead."
        color: Colors.outline
        font.family: Config.theme.font
        font.pixelSize: 12
    }
}
