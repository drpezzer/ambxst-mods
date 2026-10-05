pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ambxst Roadie (drpezzer.roadie): the root commands of the AI sidebar.
//
// Claude Code cannot run a command that needs root from the sidebar: sudo has
// no terminal to ask for the password on. Its bridge holds such a command
// back, and Ai.qml puts it in a box of its own under the reply
// (RoadieSudoBox): "Run this sudo command?".
//
//   Yes   the buttons give way to a field for the password (unless sudo
//         does not need one right now). With it, the command is run here,
//         exactly as written (roadie_sudo_run.sh). Its output shows in the
//         box as it arrives, and when it ends the output goes back to Claude
//         as the next message, so it carries on by itself.
//   No    nothing runs. What the user sends next tells Claude so
//         (ClaudeCodeStrategy.sudoNote).
//
// The box is a message of the chat ({ role: "system", sudo: { command, cwd,
// state, output, exitCode } }) and what becomes of it is kept there. One
// command at a time. The process lives here and not in the box: the chat's
// delegates are rebuilt whenever the chat changes.
//
// The password goes from the field to the runner's stdin and nowhere else: it
// is not kept here once written, and never reaches the chat, a file, an
// argument or the environment.
Singleton {
    id: root

    readonly property string runScript: Qt.resolvedUrl("roadie_sudo_run.sh").toString().replace(/^file:\/\//, "")
    // What goes back to Claude, and is kept in the chat: the end of it.
    readonly property int keep: 12000

    // The box that shows the password field: { chatId, index }, or null.
    property var asking: null
    // Said under that field: the last password was not accepted.
    property string problem: ""

    property bool running: false
    property bool stopped: false
    property bool checked: false   // run with a typed password
    property string chatId: ""
    property int index: -1
    property string command: ""
    property string output: ""
    property string secret: ""     // on its way to the runner's stdin

    function box(i) {
        const m = Ai.currentChat[i];
        return (m && m.sudo) ? m : null;
    }

    function update(i, patch) {
        let chat = Array.from(Ai.currentChat);
        chat[i] = Object.assign({}, chat[i], { sudo: Object.assign({}, chat[i].sudo, patch) });
        Ai.currentChat = chat;
        Ai.saveCurrentChat();
    }

    // Yes. Whether sudo wants a password is asked first (`sudo -n -v` asks
    // nobody and fails when it does).
    function approve(i) {
        const m = root.box(i);
        if (root.running || probe.running || !m || m.sudo.state !== "pending")
            return;
        root.chatId = Ai.currentChatId;
        root.index = i;
        root.command = m.sudo.command;
        root.problem = "";
        probe.running = true;
    }

    // The password field's Enter.
    function submit(password) {
        if (root.running || !root.asking || password === "")
            return;
        root.asking = null;
        root.problem = "";
        root.start(password);
    }

    // Back to Yes / No.
    function back() {
        root.asking = null;
        root.problem = "";
    }

    function start(password) {
        const m = Ai.currentChatId === root.chatId ? root.box(root.index) : null;
        if (!m || m.sudo.command !== root.command || m.sudo.state !== "pending")
            return;
        root.output = "";
        root.stopped = false;
        root.checked = password !== "";
        root.secret = password;
        runner.workingDirectory = m.sudo.cwd || Quickshell.env("HOME");
        runner.command = ["bash", root.runScript, root.checked ? "check" : "plain", root.command];
        root.running = true;
        root.update(root.index, { state: "running" });
        runner.running = true;
    }

    function decline(i) {
        const m = root.box(i);
        if (m && m.sudo.state === "pending") {
            root.back();
            root.update(i, { state: "declined" });
        }
    }

    // Ends the shell the command was started from. What already runs as root
    // cannot be signalled from here; it ends when it next writes to the pipe
    // nobody reads any more.
    function stop() {
        if (!root.running)
            return;
        root.stopped = true;
        runner.signal(15);
    }

    function finished(exitCode) {
        root.running = false;
        root.secret = "";
        if (root.checked && exitCode === 77 && !root.stopped) {
            // The password was not accepted and nothing was run: ask again.
            if (Ai.currentChatId === root.chatId && root.box(root.index)) {
                root.update(root.index, { state: "pending" });
                root.problem = "That password was not accepted.";
                root.asking = { chatId: root.chatId, index: root.index };
            } else {
                root.patchFile({ state: "pending" });
            }
            return;
        }
        const patch = {
            state: root.stopped ? "cancelled" : "done",
            exitCode: exitCode,
            output: root.output
        };
        const m = Ai.currentChatId === root.chatId ? root.box(root.index) : null;
        if (!m || m.sudo.command !== root.command) {
            // Another chat is open by now: the result goes into the file.
            root.patchFile(patch);
            return;
        }
        root.update(root.index, patch);
        // Claude takes it from here, if it is still its turn to.
        const claude = Ai.currentModel && Ai.currentModel.provider === "claude-code";
        if (patch.state === "done" && claude && !Ai.isLoading && root.index === Ai.currentChat.length - 1) {
            Ai.isLoading = true;
            Ai.lastError = "";
            Ai.makeRequest();
        }
    }

    function patchFile(patch) {
        chatFile.path = Ai.chatDir + "/" + root.chatId + ".json";
        chatFile.reload();
        chatFile.waitForJob();
        try {
            let chat = JSON.parse(chatFile.text());
            const m = chat[root.index];
            if (m && m.sudo && m.sudo.command === root.command) {
                m.sudo = Object.assign({}, m.sudo, patch);
                chatFile.setText(JSON.stringify(chat, null, 2));
            }
        } catch (e) {
            console.warn("RoadieSudo: could not file the result of", root.command, "in chat", root.chatId, e);
        }
    }

    FileView {
        id: chatFile
        blockLoading: true
        printErrors: false
    }

    Process {
        id: probe
        command: ["sudo", "-n", "-v"]
        onExited: exitCode => {
            if (Ai.currentChatId !== root.chatId || !root.box(root.index))
                return;
            if (exitCode === 0)
                root.start("");
            else
                root.asking = { chatId: root.chatId, index: root.index };
        }
    }

    Process {
        id: runner
        stdinEnabled: true
        onStarted: {
            if (root.checked)
                runner.write(root.secret + "\n");
            root.secret = "";
        }
        stdout: SplitParser {
            onRead: data => {
                const all = root.output + data + "\n";
                root.output = all.length > root.keep ? all.substring(all.length - root.keep) : all;
            }
        }
        onExited: exitCode => root.finished(exitCode)
    }
}
