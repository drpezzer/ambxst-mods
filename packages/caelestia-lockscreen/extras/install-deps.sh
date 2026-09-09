#!/usr/bin/env bash
# Installs what the Caelestia Style Lockscreen needs on Arch. Run it yourself:
# Ambxst mods never run scripts, by design, so this is not automatic.
#
#   caelestia-shell  the M3Shapes and Caelestia QML plugins (library only, never started)
#   grim             screenshots the desktop to blur behind the lock
#   fortune-mod      the quote in the bottom-left (optional; the label is empty without it)
set -euo pipefail
helper=""
for h in yay paru; do command -v "$h" >/dev/null 2>&1 && { helper=$h; break; }; done
[ -n "$helper" ] || { echo "Needs an AUR helper (yay or paru): caelestia-shell is an AUR package." >&2; exit 1; }
exec "$helper" -S --needed caelestia-shell grim fortune-mod
