import QtQuick

// LockText that decodes into place: every glyph cycles through katakana and
// settles left to right over `revealDuration`. Set `source`, not `text`; the
// displayed `text` is owned by the animation. Runs whenever `source` changes,
// so the clock re-scrambles each minute and the quote decodes when it lands.
LockText {
    id: root

    property string source: ""
    // The composition sits invisible behind the padlock intro, so the decode
    // has to wait for the reveal rather than run at creation. Bind this to
    // "the text can be seen now"; each rise to true restarts the decode.
    property bool active: true
    // Longer strings get a little longer to decode, capped so the quote never
    // drags on while the password field is already waiting.
    property int revealDuration: Math.min(1400, 500 + source.length * 8)
    property int tickInterval: 40
    property string glyphs: "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"

    property real _startedAt: 0

    text: ""

    onSourceChanged: restart()
    onActiveChanged: restart()
    Component.onCompleted: restart()

    function restart(): void {
        if (source === "" || !active) {
            ticker.stop();
            text = source;
            return;
        }
        _startedAt = Date.now();
        ticker.restart();
        tick();
    }

    function tick(): void {
        const progress = Math.min(1, (Date.now() - _startedAt) / revealDuration);
        const n = source.length;
        const resolved = Math.floor(progress * n);
        let out = "";
        for (let i = 0; i < n; i++) {
            const c = source[i];
            if (i < resolved || c === " " || c === "\n" || c === ":" || c === ",")
                out += c;
            else
                out += glyphs[Math.floor(Math.random() * glyphs.length)];
        }
        text = out;
        if (progress >= 1) {
            text = source;
            ticker.stop();
        }
    }

    Timer {
        id: ticker

        interval: root.tickInterval
        repeat: true
        onTriggered: root.tick()
    }
}
