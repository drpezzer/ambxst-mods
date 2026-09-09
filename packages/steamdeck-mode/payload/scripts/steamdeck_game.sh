#!/usr/bin/env bash
#
# Prints the name of the Steam game currently running, or nothing at all.
# Used by Steamdeck Mode's lock screen for the "You're currently playing X"
# line, polled every few seconds while the lock is up.
#
# Reads Steam directly rather than asking MoonDeck Buddy: Buddy's API on :59999
# is HTTPS behind the Deck pairing handshake, which is a lot of machinery for
# one string, and it would make the lock screen's text depend on the Deck
# having finished pairing. Steam is already the source of truth locally.
#
# Detection is via Steam's launch wrapper: every game Steam starts on Linux is
# run under `reaper SteamLaunch AppId=<id> --`, whatever the launch options or
# Proton version. `registry.vdf`'s RunningAppID looked like the obvious source
# but is not written on Linux.

set -uo pipefail

appid=$(pgrep -a -f 'SteamLaunch AppId=' 2>/dev/null |
	grep -oE 'AppId=[0-9]+' | head -1 | cut -d= -f2)

[ -n "${appid:-}" ] || exit 0

# Resolve the name from the local app manifest. Both library roots are read
# from libraryfolders.vdf rather than hardcoded, so a new drive added later
# (Harrison keeps a second library on /mnt/steam-library) needs no change here.
steam_root="$HOME/.steam/steam"
libs=$(grep -oE '"/[^"]*"' "$steam_root/steamapps/libraryfolders.vdf" 2>/dev/null | tr -d '"')

for lib in $steam_root $libs; do
	manifest="$lib/steamapps/appmanifest_${appid}.acf"
	if [ -f "$manifest" ]; then
		# "name"		"Game Title"  -> Game Title
		name=$(grep -m1 -oP '"name"\s+"\K[^"]*' "$manifest" 2>/dev/null)
		if [ -n "${name:-}" ]; then
			printf '%s' "$name"
			exit 0
		fi
	fi
done

# Running but unidentifiable (a shortcut, or a manifest on an unmounted drive).
printf 'Game %s' "$appid"
