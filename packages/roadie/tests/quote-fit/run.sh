#!/usr/bin/env bash
# Lays every built-in farewell quote (plus one absurdly long custom line) out in
# the real FarewellQuote.qml at 14 screen sizes and 4 fonts, headless, and
# fails unless each one is a single line, inside the line width, not elided.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); pkg=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$here/harness.qml" "$pkg/payload/modules/notch/FarewellQuote.qml" "$tmp/"
python3 - "$pkg/payload/modules/services/ShellFarewell.qml" "$tmp/quotes.json" <<'PY'
import re, json, sys
s = open(sys.argv[1]).read()
q = [{"text": a, "source": b} for a, b in re.findall(r'\{ text: "((?:[^"\\]|\\.)*)", source: "((?:[^"\\]|\\.)*)" \}', s) if a]
q.append({"text": "A custom line somebody typed into roadie-quotes.json that simply goes on and on, far past anything a film ever said on the way out of a room, to see what the fit does when there is no hope at all of a sensible size.", "source": "A very long source name that also goes on for quite a while, The Extended Director's Cut, Part Two"})
json.dump(q, open(sys.argv[2], "w"))
PY
qml=$(command -v qml6 || command -v qml || echo /usr/lib/qt6/bin/qml)
out=$(QT_FORCE_STDERR_LOGGING=1 QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen timeout 120 "$qml" "$tmp/harness.qml" 2>&1 | sed 's/^qml: //')
echo "$out" | grep -v '^  custom'
echo "$out" | grep -q '^ALL ONE LINE, NONE ELIDED$'
