#!/usr/bin/env bash
# One short quote for the lockscreen's bottom-left label.
#
# Default output is wrapped to 60 columns and pango-escaped, for hyprlock's
# label. With --raw it emits a single unwrapped, unescaped line, for the
# Quickshell lockscreen, which wraps and escapes text itself.

set -o pipefail

FORTUNE_BIN=/usr/bin/fortune
raw=0
[[ ${1:-} == --raw ]] && raw=1

[[ -x "$FORTUNE_BIN" ]] || exit 0

# Only pass databases that are actually installed - fortune aborts on a missing
# one, which would blank the label (pratchett, for instance, lives in the AUR).
dbs=()
for db in science wisdom literature pratchett; do
    [[ -f /usr/share/fortune/$db ]] && dbs+=("$db")
done

"$FORTUNE_BIN" -e -s -n 120 "${dbs[@]}" 2>/dev/null \
    | expand -t 4 \
    | awk '
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "")
                next

            if ($0 ~ /^--[[:space:]]*/)
                in_attribution = 1
            else if (!in_attribution)
                quote = quote (quote == "" ? "" : " ") $0
        }
        END {
            if (quote != "")
                print quote
        }
    ' \
    | if (( raw )); then
        cat
    else
        fold -s -w 60 | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
    fi
