pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services

// Ambxst Roadie (drpezzer.roadie): the farewell.
//
// Reboot and Power Off from the power menu do not run at once. The notch the
// menu sits in swells until it is the whole screen (`expand`, every screen in
// step), the ground goes solid (`solid`), a line said on the way out of some
// film or show fades in (`text`) -- a goodbye for a shutdown, a "back in a
// second" for a reboot -- and only when it has been up long enough to read is
// the command run. The quote stays on screen until the session is gone.
//
//   expand   0 .. D          InOutCubic   (D = farewellDuration)
//   chrome   bar pills and dock fade to black over the first 70% of that
//   solid    D .. D + 250    OutCubic
//   text     D + 150 .. +700 OutCubic
//   hold     farewellHold + 40 ms per character
//   commit   veil told to hold plain background, command runs
//
// Escape backs out any time before the commit and plays it all in reverse; a
// click, Return or Space ends the hold early. If the command fails, or the
// machine is somehow still up 20 s later, the farewell backs out by itself.
//
// Quotes are drawn from a shuffled bag kept in
// $XDG_STATE_HOME/ambxst/roadie-farewell.json, so none repeats until all of
// that kind have been shown. A user file ~/.config/ambxst/roadie-quotes.json
//   { "shutdown": [ { "text": "...", "source": "..." }, "plain string" ],
//     "reboot": [ ... ], "hidden": [ "texts of built-in lines to skip" ],
//     "replace": false }
// adds to the lists (or stands in for them with "replace": true); the
// editor under the mod's settings in Settings > Mods writes the same file.
Singleton {
    id: root

    // ─── settings (Settings > Mods > Ambxst Roadie) ────────────────────
    property bool farewellEnabled: true
    property int farewellDuration: 900
    property int farewellHold: 1500
    property bool showSource: false

    function applyValues(values) {
        if (!values)
            return;
        if (values.farewellEnabled !== undefined)
            root.farewellEnabled = !!values.farewellEnabled;
        if (values.farewellSource !== undefined)
            root.showSource = !!values.farewellSource;
        const d = Number(values.farewellDuration);
        if (values.farewellDuration !== undefined && !isNaN(d) && d >= 0)
            root.farewellDuration = d;
        const h = Number(values.farewellHold);
        if (values.farewellHold !== undefined && !isNaN(h) && h >= 0)
            root.farewellHold = h;
    }

    function loadSettings() {
        if (typeof ModsService === "undefined" || typeof ModsService.getSettings !== "function")
            return;
        ModsService.getSettings(ShellTransitions.modId, (settings, error) => {
            if (error || !settings)
                return;
            root.applyValues(settings.values);
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId !== ShellTransitions.modId)
                return;
            const values = {};
            values[key] = value;
            root.applyValues(values);
        }
    }

    Component.onCompleted: {
        root.loadSettings();
        // The bag's directory does not exist on a machine no other Ambxst
        // state has been written on yet.
        stateDir.running = true;
    }

    Process {
        id: stateDir
        running: false
        command: ["mkdir", "-p", (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst"]
    }

    // ─── state ─────────────────────────────────────────────────────────
    property bool active: false
    property bool committed: false
    property bool dryRun: false
    property bool backingOut: false
    property bool holding: false
    property string kind: ""        // "shutdown" | "reboot"
    property string command: ""
    property string screenName: ""  // the screen the quote is shown on ("" = all)
    property string quote: ""
    property string source: ""

    property real expand: 0
    property real solid: 0
    property real text: 0

    // Bar pills and dock: gone by the time the notch is 70% of the way.
    readonly property real chromeOpacity: Math.max(0, 1 - root.expand / 0.7)

    readonly property bool animate: (Config.animDuration !== undefined ? Config.animDuration : 300) > 0
    readonly property int expandMs: root.animate ? root.farewellDuration : 0
    readonly property int holdMs: root.farewellHold + root.quote.length * 40

    // ─── quotes ────────────────────────────────────────────────────────
    // Every line ends in a full stop, whatever it ended in on screen.
    readonly property var builtin: ({
        shutdown: [
            { text: "See you in another life, brother.", source: "Lost" },
            { text: "In case I don't see ya, good afternoon, good evening, and good night.", source: "The Truman Show" },
            { text: "Namaste, and good luck.", source: "Lost" },
            { text: "Hasta la vista, baby.", source: "Terminator 2: Judgment Day" },
            { text: "So long, and thanks for all the fish.", source: "The Hitchhiker's Guide to the Galaxy" },
            { text: "After all, tomorrow is another day.", source: "Gone with the Wind" },
            { text: "So long, partner.", source: "Toy Story 3" },
            { text: "I'll be right here.", source: "E.T. the Extra-Terrestrial" },
            { text: "Live long and prosper.", source: "Star Trek" },
            { text: "I have been, and always shall be, your friend.", source: "Star Trek II: The Wrath of Khan" },
            { text: "Second star to the right, and straight on till morning.", source: "Star Trek VI: The Undiscovered Country" },
            { text: "That's all, folks.", source: "Looney Tunes" },
            { text: "See you, space cowboy.", source: "Cowboy Bebop" },
            { text: "Mischief managed.", source: "Harry Potter and the Prisoner of Azkaban" },
            { text: "Dave, my mind is going. I can feel it.", source: "2001: A Space Odyssey" },
            { text: "All those moments will be lost in time, like tears in rain.", source: "Blade Runner" },
            { text: "I don't want to go.", source: "Doctor Who" },
            { text: "Goodbye, Mr. Anderson.", source: "The Matrix" },
            { text: "Everything that has a beginning has an end.", source: "The Matrix Revolutions" },
            { text: "So long, farewell, auf Wiedersehen, goodbye.", source: "The Sound of Music" },
            { text: "Good night, sweet prince.", source: "The Big Lebowski" },
            { text: "Good night, Westley. Good work. Sleep well. I'll most likely kill you in the morning.", source: "The Princess Bride" },
            { text: "I will not say: do not weep; for not all tears are an evil.", source: "The Lord of the Rings: The Return of the King" },
            { text: "Roads? Where we're going, we don't need roads.", source: "Back to the Future" },
            { text: "See you on the other side, Ray.", source: "Ghostbusters" },
            { text: "Stay classy, San Diego.", source: "Anchorman" },
            { text: "Au revoir, Shoshanna.", source: "Inglourious Basterds" },
            { text: "And in the morning, I'm making waffles.", source: "Shrek" },
            { text: "Good night, John-Boy.", source: "The Waltons" },
            { text: "Goodnight, Seattle.", source: "Frasier" },
            { text: "I'm finished.", source: "There Will Be Blood" }
        ],
        reboot: [
            { text: "I'll be back.", source: "The Terminator" },
            { text: "Have you tried turning it off and on again.", source: "The IT Crowd" },
            { text: "Hold on to your butts.", source: "Jurassic Park" },
            { text: "We have to go back.", source: "Lost" },
            { text: "Smoke me a kipper, I'll be back for breakfast.", source: "Red Dwarf" },
            { text: "I'll be back before you can say blueberry pie.", source: "Pulp Fiction" },
            { text: "If I'm not back in five minutes, just wait longer.", source: "Ace Ventura: Pet Detective" },
            { text: "I'll be right back.", source: "Scream" },
            { text: "Be seeing you.", source: "The Prisoner" },
            { text: "Same Bat-time, same Bat-channel.", source: "Batman" },
            { text: "To be continued.", source: "Back to the Future" },
            { text: "We'll be right back after these messages.", source: "Saturday morning television" },
            { text: "Don't blink.", source: "Doctor Who" },
            { text: "Well, it's Groundhog Day. Again.", source: "Groundhog Day" },
            { text: "Let's do the Time Warp again.", source: "The Rocky Horror Picture Show" },
            { text: "Once more, with feeling.", source: "Buffy the Vampire Slayer" },
            { text: "Just when I thought I was out, they pull me back in.", source: "The Godfather Part III" },
            { text: "And now for something completely different.", source: "Monty Python's Flying Circus" },
            { text: "It's just a flesh wound.", source: "Monty Python and the Holy Grail" },
            { text: "I got better.", source: "Monty Python and the Holy Grail" },
            { text: "There's a big difference between mostly dead and all dead.", source: "The Princess Bride" },
            { text: "Death cannot stop true love. All it can do is delay it for a while.", source: "The Princess Bride" },
            { text: "What is dead may never die.", source: "Game of Thrones" },
            { text: "Pay no attention to that man behind the curtain.", source: "The Wizard of Oz" },
            { text: "Fasten your seatbelts. It's going to be a bumpy night.", source: "All About Eve" },
            { text: "Hang on, lads. I've got a great idea.", source: "The Italian Job" },
            { text: "Live. Die. Repeat.", source: "Edge of Tomorrow" },
            { text: "Wait for it.", source: "How I Met Your Mother" },
            { text: "Punch it, Chewie.", source: "The Empire Strikes Back" },
            { text: "Make it so.", source: "Star Trek: The Next Generation" }
        ]
    })

    property var userQuotes: null

    function normalise(list) {
        const out = [];
        for (const q of (list || [])) {
            const t = (typeof q === "string" ? q : (q && q.text) || "").trim();
            if (t.length > 0)
                out.push({ text: t, source: (q && typeof q === "object" && q.source) ? String(q.source) : "" });
        }
        return out;
    }

    // The user file, tidied: { shutdown: [...], reboot: [...], hidden: [texts
    // of built-in lines switched off], replace: bool }.
    function userDoc() {
        const u = root.userQuotes || {};
        return {
            shutdown: root.normalise(u.shutdown),
            reboot: root.normalise(u.reboot),
            hidden: Array.isArray(u.hidden) ? u.hidden.filter(t => typeof t === "string") : [],
            replace: u.replace === true
        };
    }

    function quotesFor(kind) {
        const doc = root.userDoc();
        const own = (root.builtin[kind] || []).filter(q => doc.hidden.indexOf(q.text) === -1);
        const extra = doc[kind] || [];
        return (doc.replace && extra.length > 0) ? extra : own.concat(extra);
    }

    // ─── editing (Settings > Mods > Ambxst Roadie, RoadieQuotesEditor) ──
    function saveUserDoc(doc) {
        root.userQuotes = doc;
        userFile.setText(JSON.stringify(doc, null, 2) + "\n");
    }

    function addUserQuote(kind, text, source) {
        if (kind !== "shutdown" && kind !== "reboot")
            return false;
        let t = String(text || "").trim().replace(/\s+/g, " ");
        if (t.length === 0)
            return false;
        // Every line ends in a full stop.
        if (!/[.!?…"”']$/.test(t))
            t += ".";
        const doc = root.userDoc();
        if (doc[kind].some(q => q.text === t))
            return true;
        doc[kind].push({ text: t, source: String(source || "").trim() });
        root.saveUserDoc(doc);
        return true;
    }

    function removeUserQuote(kind, index) {
        const doc = root.userDoc();
        if (!doc[kind] || index < 0 || index >= doc[kind].length)
            return;
        doc[kind].splice(index, 1);
        root.saveUserDoc(doc);
    }

    function setHidden(text, hidden) {
        const doc = root.userDoc();
        doc.hidden = doc.hidden.filter(t => t !== text);
        if (hidden)
            doc.hidden.push(text);
        root.saveUserDoc(doc);
    }

    function setReplace(on) {
        const doc = root.userDoc();
        doc.replace = !!on;
        root.saveUserDoc(doc);
    }

    FileView {
        id: userFile
        path: Quickshell.env("HOME") + "/.config/ambxst/roadie-quotes.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.userQuotes = JSON.parse(text());
            } catch (e) {
                console.warn("ShellFarewell: roadie-quotes.json is not valid JSON:", e);
                root.userQuotes = null;
            }
        }
        onLoadFailed: root.userQuotes = null
    }

    // The bag: texts of the quotes not shown yet, per kind.
    property var bag: ({})

    FileView {
        id: bagFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/roadie-farewell.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                root.bag = JSON.parse(text()) || {};
            } catch (e) {
                root.bag = {};
            }
        }
    }

    function draw(kind) {
        const all = root.quotesFor(kind);
        if (all.length === 0)
            return { text: "", source: "" };
        const known = {};
        for (const q of all)
            known[q.text] = q;
        let left = ((root.bag && root.bag[kind]) || []).filter(t => known[t] !== undefined);
        if (left.length === 0) {
            left = all.map(q => q.text);
            // A fresh bag does not open with the line the last one closed on.
            if (left.length > 1 && root.bag && root.bag.last && root.bag.last[kind])
                left = left.filter(t => t !== root.bag.last[kind]);
        }
        const pick = left[Math.floor(Math.random() * left.length)];
        return known[pick];
    }

    function spend(kind, text) {
        const next = Object.assign({}, root.bag || {});
        const all = root.quotesFor(kind).map(q => q.text);
        let left = (next[kind] || []).filter(t => all.indexOf(t) !== -1);
        if (left.length === 0)
            left = all;
        next[kind] = left.filter(t => t !== text);
        next.last = Object.assign({}, next.last || {});
        next.last[kind] = text;
        root.bag = next;
        bagFile.setText(JSON.stringify(next));
    }

    // ─── entry points ──────────────────────────────────────────────────
    function kindOf(command) {
        const c = String(command || "");
        if (/\breboot\b/.test(c))
            return "reboot";
        if (/\b(poweroff|shutdown|halt)\b/.test(c))
            return "shutdown";
        return "";
    }

    // Called by the power menu. True = the farewell has taken the command.
    function intercept(command) {
        if (root.active)
            return true;
        if (!root.farewellEnabled)
            return false;
        const kind = root.kindOf(command);
        if (kind === "")
            return false;
        const mon = AxctlService.focusedMonitor;
        return root.begin(kind, command, mon && mon.name ? mon.name : "", false);
    }

    function begin(kind, command, screenName, dryRun) {
        if (root.active)
            return false;
        const q = root.draw(kind);
        root.kind = kind;
        root.command = command;
        root.screenName = screenName || "";
        root.dryRun = !!dryRun;
        root.quote = q.text;
        root.source = q.source || "";
        root.committed = false;
        root.backingOut = false;
        root.holding = false;
        root.expand = 0;
        root.solid = 0;
        root.text = 0;
        root.active = true;
        console.log("ShellFarewell:", kind, root.dryRun ? "(preview)" : "", "--", root.quote);
        backOut.stop();
        timeline.restart();
        return true;
    }

    // End the hold early. Only once the quote is fully up, so the second half
    // of a double click on the power button cannot skip the whole thing.
    function skip() {
        if (!root.active || root.committed || root.backingOut || !root.holding)
            return;
        timeline.stop();
        root.holding = false;
        root.commit();
    }

    function cancel() {
        if (!root.active || root.backingOut || (root.committed && !root.dryRun))
            return;
        root.retreat();
    }

    function retreat() {
        timeline.stop();
        root.holding = false;
        failsafe.stop();
        previewEnd.stop();
        root.backingOut = true;
        backOut.restart();
    }

    function commit() {
        if (root.committed)
            return;
        root.committed = true;
        if (root.dryRun) {
            previewEnd.restart();
            return;
        }
        root.spend(root.kind, root.quote);
        // No wallpaper flash if the shell dies before the compositor does.
        ShellTransitions.send({ type: "leaving" });
        runner.command = ["/bin/bash", "-c", root.command];
        runner.running = true;
        failsafe.restart();
    }

    SequentialAnimation {
        id: timeline
        NumberAnimation {
            target: root
            property: "expand"
            to: 1
            duration: root.expandMs
            easing.type: Easing.InOutCubic
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "solid"
                to: 1
                duration: root.animate ? 250 : 0
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: root.animate ? 150 : 0
                }
                NumberAnimation {
                    target: root
                    property: "text"
                    to: 1
                    duration: root.animate ? 700 : 0
                    easing.type: Easing.OutCubic
                }
            }
        }
        ScriptAction {
            script: root.holding = true
        }
        PauseAnimation {
            duration: root.holdMs
        }
        ScriptAction {
            script: {
                root.holding = false;
                root.commit();
            }
        }
    }

    SequentialAnimation {
        id: backOut
        NumberAnimation {
            target: root
            property: "text"
            to: 0
            duration: root.animate ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "solid"
            to: 0
            duration: root.animate ? 150 : 0
        }
        // The power menu closes as the notch shrinks, so it lands on the
        // plain notch rather than back on the buttons.
        ScriptAction {
            script: Visibilities.setActiveModule("")
        }
        NumberAnimation {
            target: root
            property: "expand"
            to: 0
            duration: Math.round(root.expandMs * 0.75)
            easing.type: Easing.InOutCubic
        }
        ScriptAction {
            script: {
                root.active = false;
                root.backingOut = false;
                root.committed = false;
                root.dryRun = false;
            }
        }
    }

    Process {
        id: runner
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.active && !root.dryRun) {
                console.warn("ShellFarewell:", root.command, "exited", exitCode, "-- backing out");
                ShellTransitions.send({ type: "staying" });
                root.retreat();
            }
        }
    }

    // Still here? Then nothing is shutting down (an inhibitor, a polkit
    // prompt nobody can see under the sheet).
    Timer {
        id: failsafe
        interval: 20000
        onTriggered: {
            if (!root.active)
                return;
            console.warn("ShellFarewell: still up 20 s after", root.command, "-- backing out");
            ShellTransitions.send({ type: "staying" });
            root.retreat();
        }
    }

    Timer {
        id: previewEnd
        interval: 1200
        onTriggered: root.retreat()
    }
}
