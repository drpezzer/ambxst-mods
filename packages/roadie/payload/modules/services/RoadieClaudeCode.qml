pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "ai"
import "ai/strategies"

// Ambxst Roadie (drpezzer.roadie): Claude Code in the AI sidebar.
//
// Ambxst's sidebar talks to providers that want an API key. With the switch
// under Settings > AI on, the Claude Code CLI installed on this machine is one
// more provider beside them: its models join the sidebar's model list, and a
// message sent to one runs a turn of `claude` under the login the CLI already
// has. The API providers are untouched and stay in the list.
//
// This holds what Ai.qml needs for that: the models to offer and the strategy
// (ClaudeCodeStrategy, which hands the turn to roadie_claude_code.py). It never
// refers to Ai, so Ai can refer to it from its first moment.
//
// It also reads what the bridge files after every turn (its state file): each
// chat's label as `claude --resume` would show it, the model that answered,
// how full the context window is, how much of the 5-hour limit is used, and
// what the CLI's model aliases stand for. The sidebar's history list and the
// status row above its input (RoadieAiStatus) show that.
Singleton {
    id: root

    readonly property bool enabled: RoadieSettings.claudeCode
    readonly property string helper: Qt.resolvedUrl("roadie_claude_code.py").toString().replace(/^file:\/\//, "")

    // Ambxst's stock prompt talks about tools Claude Code does not have; only
    // a prompt the user wrote is passed on.
    readonly property string stockPrompt: "You are a helpful assistant running on a Linux system. You have access to some tools to control the system."
    readonly property string userPrompt: {
        const p = (Config.ai && Config.ai.systemPrompt) ? String(Config.ai.systemPrompt).trim() : "";
        return p === root.stockPrompt ? "" : p;
    }

    property ClaudeCodeStrategy strategy: ClaudeCodeStrategy {
        helper: root.helper
        access: RoadieSettings.claudeCodeAccess
        cwd: RoadieSettings.claudeCodeDir
        systemPrompt: root.userPrompt
    }

    // "claude-code" is whatever model Claude Code itself is set to; the rest
    // are the CLI's own aliases, so they keep meaning the newest of each.
    readonly property var catalog: [
        { id: "claude-code", name: "Claude Code", description: "The model your Claude Code is set to" },
        { id: "claude-code/fable", name: "Claude Code · Fable", description: "Claude Code on the newest Fable" },
        { id: "claude-code/opus", name: "Claude Code · Opus", description: "Claude Code on the newest Opus" },
        { id: "claude-code/sonnet", name: "Claude Code · Sonnet", description: "Claude Code on the newest Sonnet" },
        { id: "claude-code/haiku", name: "Claude Code · Haiku", description: "Claude Code on the newest Haiku, the quickest" }
    ]

    property var all: []
    // What the sidebar's model list should hold: everything while the switch
    // is on, nothing while it is off.
    readonly property var offered: root.enabled ? root.all : []

    // Emitted when the user flips the switch on (not at start): the sidebar
    // moves to Claude Code then, which is what flipping it asks for.
    signal switchedOn

    Component {
        id: modelFactory
        AiModel {}
    }

    Component.onCompleted: {
        let made = [];
        for (let i = 0; i < root.catalog.length; i++) {
            const entry = root.catalog[i];
            const m = modelFactory.createObject(root, {
                name: entry.name,
                icon: Qt.resolvedUrl("../../assets/aiproviders/anthropic.svg"),
                description: entry.description,
                endpoint: "claude-code",
                model: entry.id,
                provider: "claude-code",
                requires_key: false,
                api_format: "Claude Code",
                customCurlTemplate: root.strategy.commandFor("")
            });
            if (m)
                made.push(m);
        }
        root.all = made;
    }

    function setEnabled(on) {
        if (on === root.enabled)
            return;
        RoadieSettings.set("claudeCode", on);
        if (on)
            root.switchedOn();
    }

    // ── what the bridge has filed ─────────────────────────────────────────
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/roadie-claude-code.json"

    property var chats: ({})     // chat id -> { title, model, used, window }
    property var limit: null     // { fiveHour: 0..1, resetsAt: epoch seconds }
    property var aliases: ({})   // "" | fable | opus | ... -> the model id it stands for
    property string stateText: ""
    signal infoChanged

    function chat(id) {
        return root.chats[id] || null;
    }

    // The sidebar's history, with a Claude Code chat under its session's label.
    function labelled(history) {
        if (!root.enabled || !history)
            return history;
        let out = [];
        for (let i = 0; i < history.length; i++) {
            const info = root.chats[history[i].id];
            out.push(info && info.title ? Object.assign({}, history[i], { title: info.title }) : history[i]);
        }
        return out;
    }

    function readState(text) {
        if (text === root.stateText)
            return;
        root.stateText = text;
        let state = {};
        try {
            state = JSON.parse(text) || {};
        } catch (e) {
            return;
        }
        const sessions = state.sessions || {};
        let byChat = {};
        let stamps = {};
        for (const sid in sessions) {
            const s = sessions[sid];
            if (!s || !s.chat || (stamps[s.chat] || 0) > (s.at || 0))
                continue;
            stamps[s.chat] = s.at || 0;
            byChat[s.chat] = {
                title: s.label || s.title || "",
                model: s.model || "",
                used: s.context ? (s.context.used || 0) : 0,
                window: s.context ? (s.context.window || 0) : 0
            };
        }
        root.chats = byChat;
        root.limit = (state.limit && typeof state.limit.fiveHour === "number") ? state.limit : null;
        root.aliases = state.models || {};
        root.infoChanged();
    }

    FileView {
        id: stateFile
        path: root.enabled ? root.statePath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readState(text())
    }

    // Read the sessions' labels again (one may have been renamed or carried on
    // in a terminal) and pick the file up; once more a little later, for the
    // title a first reply is given a few seconds after it lands.
    function refresh() {
        if (!root.enabled)
            return;
        if (!refreshProcess.running)
            refreshProcess.running = true;
        settle.restart();
    }
    property Process refreshProcess: Process {
        command: ["python3", root.helper, "refresh"]
        onExited: stateFile.reload()
    }
    property Timer settle: Timer {
        interval: 7000
        onTriggered: stateFile.reload()
    }

    // What the aliases stand for is asked once per shell run; the bridge
    // itself skips the question while its answer is recent.
    property bool modelsAsked: false
    function ensureModels() {
        if (!root.enabled || root.modelsAsked)
            return;
        root.modelsAsked = true;
        modelsProcess.running = true;
    }
    property Process modelsProcess: Process {
        command: ["python3", root.helper, "models"]
        onExited: stateFile.reload()
    }

    // "claude-fable-5-1" -> "Fable 5.1", "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    function pretty(id) {
        let big = /\[1m\]$/i.test(id);
        const parts = String(id).replace(/\[1m\]$/i, "").replace(/^claude-/, "").split("-");
        let words = [];
        let numbers = [];
        for (let i = 0; i < parts.length; i++) {
            if (/^\d{6,}$/.test(parts[i]))
                continue; // a release date
            if (/^\d+$/.test(parts[i]))
                numbers.push(parts[i]);
            else if (parts[i] !== "")
                words.push(parts[i].charAt(0).toUpperCase() + parts[i].slice(1));
        }
        return (words.join(" ") + " " + numbers.join(".")).trim() + (big ? " (1M)" : "");
    }

    function aliasOf(model) {
        const slash = model.model.indexOf("/");
        return slash === -1 ? "" : model.model.substring(slash + 1);
    }

    // The name to show for a model of the sidebar: for a Claude Code model
    // the model it stands for right now, once that is known.
    function label(model) {
        if (!model)
            return "";
        if (model.provider !== "claude-code")
            return model.name;
        const alias = root.aliasOf(model);
        const id = root.aliases[alias];
        if (id)
            return root.pretty(id);
        return alias === "" ? "Claude Code" : alias.charAt(0).toUpperCase() + alias.slice(1);
    }

    // The models the wheel turns through: the ones of the same kind as the
    // current one (Claude Code's, or the API providers'), each name once.
    function wheel(models, current) {
        let out = [];
        if (!current)
            return out;
        const mine = current.provider === "claude-code";
        let seen = {};
        seen[root.label(current)] = true;
        for (let i = 0; i < models.length; i++) {
            const m = models[i];
            if ((m.provider === "claude-code") !== mine)
                continue;
            if (m === current) {
                out.push(m);
                continue;
            }
            const name = root.label(m);
            if (seen[name])
                continue;
            seen[name] = true;
            out.push(m);
        }
        return out;
    }

    // ── messages sent while a reply is being written ──────────────────────
    //
    // Stock sends such a message as a request of its own on top of the one
    // that is running: the running turn never sees it, its text moves into the
    // new bubble, and a second turn starts when the first ends and writes over
    // whatever is last in the chat (seen: Claude's reply in the user's bubble).
    //
    // Here it waits in `queued`, shown under the chat. While Claude Code is
    // answering it is also written into the turn's inbox, and Claude reads it
    // after the tool call it is on, as it would a message typed into the
    // terminal meanwhile; the bridge says when ("took") and Ai.qml moves it
    // into the chat at that point. What is still queued when the reply ends
    // (another provider's reply, or Claude was already done) is sent then.
    property var queued: []         // [{ id, text, attachments, claude, written }]
    property int queueSerial: 0

    function queue(text, attachments, claude) {
        root.queueSerial += 1;
        const id = ("000000" + root.queueSerial).slice(-6);
        root.queued = root.queued.concat([{
            id: id,
            text: text,
            attachments: attachments || [],
            claude: claude === true,
            written: false
        }]);
        root.deliver();
    }

    // Writes what is waiting into the running turn's inbox, once it has one.
    function deliver() {
        const inbox = root.strategy.inbox;
        if (inbox === "")
            return;
        let changed = false;
        let next = [];
        for (let i = 0; i < root.queued.length; i++) {
            let q = root.queued[i];
            if (q.claude && !q.written) {
                const file = inboxWriter.createObject(root, { path: inbox + "/" + q.id + ".json" });
                file.setText(JSON.stringify({ content: q.text, attachments: q.attachments }));
                file.destroy(3000);
                q = Object.assign({}, q, { written: true });
                changed = true;
            }
            next.push(q);
        }
        if (changed)
            root.queued = next;
    }

    // Claude has read message `id`: it leaves the queue. Returns it, or null.
    function take(id) {
        let found = null;
        let rest = [];
        for (let i = 0; i < root.queued.length; i++) {
            if (found === null && root.queued[i].id === id)
                found = root.queued[i];
            else
                rest.push(root.queued[i]);
        }
        if (found !== null)
            root.queued = rest;
        return found;
    }

    // The reply has ended: everything still waiting, and an empty queue.
    function drain() {
        const rest = root.queued;
        root.queued = [];
        return rest;
    }

    property Connections inboxWatch: Connections {
        target: root.strategy
        function onInboxChanged() {
            root.deliver();
        }
    }

    property Component inboxWriter: Component {
        FileView {
            blockWrites: true
            atomicWrites: true
            printErrors: false
        }
    }

    // ── is the CLI there? (asked by Settings > AI, never at shell start) ──
    property bool probed: false
    property bool probing: false
    property bool found: false
    property string version: ""

    function probe() {
        if (root.probing)
            return;
        root.probing = true;
        probeProcess.running = true;
    }

    property Process probeProcess: Process {
        command: ["python3", root.helper, "probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(this.text);
                    root.found = o.found === true;
                    root.version = o.version || "";
                } catch (e) {
                    root.found = false;
                    root.version = "";
                }
            }
        }
        onExited: {
            root.probing = false;
            root.probed = true;
        }
    }
}
