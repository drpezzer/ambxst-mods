import QtQuick

// Ambxst Roadie (drpezzer.roadie): Claude Code as a provider of the AI sidebar.
//
// The other strategies describe an HTTP request for curl. This one describes
// a local program: the "body" is the chat plus what the turn may do, and the
// model's curl template (Ai.qml runs one in place of curl when a model has
// it) starts roadie_claude_code.py on that body. The script runs one turn of
// the `claude` CLI, under the login the CLI already has, and prints
// {"t": "<text>"} lines (what Claude says) and {"s": "<status>"} lines (what
// it is doing meanwhile), which is all parseStreamChunk has to read.
//
// Owned and configured by RoadieClaudeCode.
ApiStrategy {
    id: strategy
    supportsStreaming: true

    property string helper: ""        // roadie_claude_code.py
    property string access: "read"    // chat | read | edit | auto
    property string cwd: ""           // "" = the home folder
    property string systemPrompt: ""  // the user's own, from Ambxst's AI config
    property string chatId: ""        // the chat being answered (set by Ai.qml per request)
    // A command the turn wanted run as root ({ command, cwd }), reported by
    // the script when the turn ends. Ai.qml makes a box of it under the reply.
    property var pendingSudo: null
    // What Claude is doing right now ("Thinking", "Running ...", "Reading
    // ..."), from the script's {"s": ...} lines. The sidebar shows it under
    // the chat while the turn runs; Ai.qml empties it when the turn ends.
    property string status: ""
    // The folder the running turn reads further messages from ({"inbox": ...},
    // "" between turns). RoadieClaudeCode writes what the user sends while a
    // reply is being written into it.
    property string inbox: ""
    property int serial: 0

    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    // `request` ties the command line to the body: Ai.qml writes the file and
    // starts the command in the same breath, and the script waits for the
    // body that carries the id it was started with.
    function commandFor(request) {
        return "exec python3 " + quote(strategy.helper) + " run '{{BODY_PATH}}' " + request;
    }

    // What the user tells Claude about a command it asked to have run as root.
    function sudoNote(sudo) {
        const output = String(sudo.output || "").trim();
        const fenced = "```\n" + (output === "" ? "(no output)" : output) + "\n```";
        switch (sudo.state) {
        case "done":
            return "I ran the command you asked for, as root:\n\n```\n" + sudo.command + "\n```\n\nExit status " + sudo.exitCode + ". Its output:\n\n" + fenced;
        case "cancelled":
            return "I started `" + sudo.command + "` as root and stopped it while it was running. Its output up to then:\n\n" + fenced;
        case "running":
            return "(I started `" + sudo.command + "` as root. How it ended is not known.)";
        default:
            return "(I chose not to run `" + sudo.command + "`.)";
        }
    }

    function getEndpoint(modelObj, apiKey) {
        return "claude-code";
    }

    function getHeaders(apiKey) {
        return [];
    }

    function getBody(messages, model, tools) {
        strategy.serial += 1;
        const request = Date.now().toString(36) + "-" + strategy.serial;
        model.customCurlTemplate = strategy.commandFor(request);
        strategy.status = "Thinking";
        strategy.inbox = "";

        // Role system is Ambxst's prompt (sent as `system`, when it is the
        // user's own) and the sidebar's notices: not part of the conversation.
        // A sudo box is neither side's message either, but what became of it
        // is something the user has to tell Claude, so it is put into their
        // next message (or is that message, when the command was run). What
        // the user says in a row is one message: a session only ever receives
        // the last one.
        let chat = [];
        const say = (text, attachments) => {
            const last = chat.length > 0 ? chat[chat.length - 1] : null;
            if (last && last.role === "user") {
                last.content = last.content ? last.content + "\n\n" + text : text;
                last.attachments = last.attachments.concat(attachments);
            } else {
                chat.push({ role: "user", content: text, attachments: attachments });
            }
        };
        for (let i = 0; i < messages.length; i++) {
            const msg = messages[i];
            if (msg.sudo) {
                say(strategy.sudoNote(msg.sudo), []);
                continue;
            }
            if (msg.role === "system")
                continue;
            if (msg.role === "user" || msg.role === "function") {
                say(msg.content || "", msg.attachments || []);
                continue;
            }
            chat.push({
                role: msg.role,
                content: msg.content || "",
                attachments: msg.attachments || []
            });
        }

        const slash = model.model.indexOf("/");
        return {
            roadie: "claude-code",
            request: request,
            model: slash === -1 ? "" : model.model.substring(slash + 1),
            access: strategy.access,
            cwd: strategy.cwd,
            system: strategy.systemPrompt,
            chat: strategy.chatId,
            messages: chat
        };
    }

    function getStreamBody(messages, model, tools) {
        return getBody(messages, model, tools);
    }

    function parseResponse(response) {
        return { content: response };
    }

    function parseStreamChunk(line) {
        const trimmed = line.trim();
        if (trimmed === "")
            return { content: "", done: false, error: null };
        try {
            const json = JSON.parse(trimmed);
            if (json.sudo && json.sudo.command)
                strategy.pendingSudo = json.sudo;
            if (typeof json.s === "string")
                strategy.status = json.s;
            if (typeof json.inbox === "string")
                strategy.inbox = json.inbox;
            // "took": Claude has read a message sent during the turn (Ai.qml
            // then shows it and starts a new bubble for what follows).
            return { content: json.t || "", took: json.took || "", done: false, error: null };
        } catch (e) {
            return { content: "", done: false, error: null };
        }
    }
}
