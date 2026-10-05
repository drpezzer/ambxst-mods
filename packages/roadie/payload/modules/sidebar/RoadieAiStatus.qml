pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Ambxst Roadie (drpezzer.roadie): the line above the AI sidebar's input.
//
//   Fable 5.1   Context 12%   5h limit 34%
//
// The model is the one the next message goes to. Pointing at it opens a small
// wheel: the model before it above, the one after it below, and the scroll
// wheel turns it, round and round. The wheel holds the models of the kind in
// use (Claude Code's, or the API providers'); a click opens the full list.
//
// Context and the 5-hour limit are Claude Code's own numbers, as of the last
// reply in this chat (RoadieClaudeCode reads them from the bridge's state
// file), so they only show for a Claude Code model.
Item {
    id: status

    signal pickerRequested

    // Show the wheel without a pointer over it.
    property bool peek: false

    readonly property var current: Ai.currentModel
    readonly property bool claudeCode: !!status.current && status.current.provider === "claude-code"
    readonly property var models: RoadieClaudeCode.wheel(Ai.models, status.current)
    readonly property int count: status.models.length
    readonly property int index: status.models.indexOf(status.current)
    readonly property bool turnable: status.count > 1 && status.index !== -1

    readonly property int rowHeight: Math.round(Styling.fontSize(-1) * 1.6)
    readonly property int textSize: Styling.fontSize(-1)

    readonly property var chat: status.claudeCode ? RoadieClaudeCode.chat(Ai.currentChatId) : null
    // A chat with nothing in it yet has used nothing; one that Claude Code
    // has not answered (it is from another provider, or older than this) is
    // not known: -1.
    readonly property bool contextKnown: !!status.chat && status.chat.window > 0
    readonly property int contextPercent: Ai.currentChat.length === 0 ? 0
        : (status.contextKnown ? Math.min(100, Math.round(100 * status.chat.used / status.chat.window)) : -1)
    readonly property var limit: status.claudeCode ? RoadieClaudeCode.limit : null
    // Past its reset time the window is a new one.
    readonly property bool limitCurrent: !!status.limit && (!status.limit.resetsAt || status.limit.resetsAt * 1000 > status.now)
    readonly property int limitPercent: status.limitCurrent ? Math.min(100, Math.round(100 * status.limit.fiveHour)) : 0
    property real now: Date.now()

    implicitHeight: status.rowHeight
    visible: !!status.current

    function at(offset) {
        if (status.count === 0)
            return null;
        const i = status.index === -1 ? 0 : status.index;
        return status.models[(((i + offset) % status.count) + status.count) % status.count];
    }

    // +1: the model below comes up. -1: the one above comes down.
    function turn(direction) {
        if (!status.turnable)
            return;
        const next = status.at(direction);
        if (!next)
            return;
        slide.stop();
        wheelColumn.shift = direction * status.rowHeight;
        Ai.setModel(next.name);
        slide.start();
    }

    Component.onCompleted: RoadieClaudeCode.ensureModels()

    Timer {
        interval: 60000
        running: status.visible && !!status.limit
        repeat: true
        onTriggered: status.now = Date.now()
    }

    component Figure: Row {
        id: figure
        property string caption: ""
        property int percent: 0
        property string tip: ""
        property int textSize: Styling.fontSize(-1)
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: figure.caption
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: figure.textSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: figure.percent < 0 ? "–" : figure.percent + "%"
            color: figure.percent >= 85 ? Colors.error : Colors.overBackground
            font.family: Config.theme.font
            font.pixelSize: figure.textSize
            font.weight: Font.Medium
        }

        HoverHandler {
            id: figureHover
        }
        StyledToolTip {
            show: figureHover.hovered
            tooltipText: figure.tip
        }
    }

    Row {
        id: line
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: status.rowHeight
        spacing: 16

        // ─── the model, and its wheel ───────────────────────────────
        Item {
            id: wheel
            readonly property bool open: (wheelHover.hovered || status.peek) && status.turnable
            readonly property real openWidth: Math.max(nameAbove.implicitWidth, nameHere.implicitWidth, nameBelow.implicitWidth)

            width: nameHere.implicitWidth
            height: status.rowHeight
            z: 2

            // The plate the wheel turns on: only there while it is open, and
            // drawn over the chat above and the input below.
            StyledRect {
                id: plate
                variant: "popup"
                radius: Styling.radius(-4)
                enableShadow: true
                x: -10
                width: (wheel.open ? wheel.openWidth : nameHere.implicitWidth) + 20
                height: wheel.open ? status.rowHeight * 3 + 8 : status.rowHeight
                y: (status.rowHeight - height) / 2
                opacity: wheel.open ? 1 : 0
                visible: opacity > 0

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on width {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Three names, one row apart; closed, only the middle row shows.
            Item {
                id: wheelWindow
                x: 0
                width: Math.max(wheel.openWidth, nameHere.implicitWidth)
                height: plate.height - (wheel.open ? 8 : 0)
                y: (status.rowHeight - height) / 2
                clip: true

                Item {
                    id: wheelColumn
                    // Where the names sit while a turn settles: one row off, then home.
                    property real shift: 0
                    width: parent.width
                    height: status.rowHeight * 3
                    y: (parent.height - height) / 2 + shift

                    NumberAnimation {
                        id: slide
                        target: wheelColumn
                        property: "shift"
                        to: 0
                        duration: Math.max(1, Config.animDuration / 2)
                        easing.type: Easing.OutCubic
                    }

                    Text {
                        id: nameAbove
                        y: 0
                        height: status.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: RoadieClaudeCode.label(status.at(-1))
                        color: Colors.outline
                        opacity: wheel.open ? 1 : 0
                        font.family: Config.theme.font
                        font.pixelSize: status.textSize
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                            }
                        }
                    }
                    Text {
                        id: nameHere
                        y: status.rowHeight
                        height: status.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: RoadieClaudeCode.label(status.current)
                        color: wheel.open ? Styling.srItem("overprimary") : Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: status.textSize
                        font.weight: Font.DemiBold
                    }
                    Text {
                        id: nameBelow
                        y: status.rowHeight * 2
                        height: status.rowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: RoadieClaudeCode.label(status.at(1))
                        color: Colors.outline
                        opacity: wheel.open ? 1 : 0
                        font.family: Config.theme.font
                        font.pixelSize: status.textSize
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                            }
                        }
                    }
                }
            }

            // What the pointer has to be over: the name, and the whole plate
            // once it is open, so reaching for the names above and below
            // does not close it.
            Item {
                x: plate.x
                y: plate.y
                width: plate.width
                height: plate.height

                HoverHandler {
                    id: wheelHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: status.pickerRequested()
                }
                WheelHandler {
                    // A mouse wheel sends 120 per notch; a touchpad sends many
                    // small steps, gathered here into notches.
                    property real gathered: 0
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        gathered += event.angleDelta.y;
                        while (gathered >= 120) {
                            gathered -= 120;
                            status.turn(-1);
                        }
                        while (gathered <= -120) {
                            gathered += 120;
                            status.turn(1);
                        }
                        event.accepted = true;
                    }
                }
            }
        }

        Figure {
            visible: status.claudeCode
            anchors.verticalCenter: parent.verticalCenter
            caption: "Context"
            percent: status.contextPercent
            tip: Ai.currentChat.length === 0 ? "Nothing in this chat yet"
                : (status.contextKnown ? Math.round(status.chat.used / 1000) + "k of " + Math.round(status.chat.window / 1000) + "k tokens in this chat"
                    : "Known after Claude Code's next reply in this chat")
        }

        Figure {
            visible: status.claudeCode && !!status.limit
            anchors.verticalCenter: parent.verticalCenter
            caption: "5h limit"
            percent: status.limitPercent
            tip: (status.limitCurrent && status.limit.resetsAt)
                ? "Resets at " + new Date(status.limit.resetsAt * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                : "As of the last reply"
        }
    }
}
