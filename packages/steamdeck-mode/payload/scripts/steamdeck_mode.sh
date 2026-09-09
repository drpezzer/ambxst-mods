#!/usr/bin/env bash
#
# Steamdeck Mode backend for Ambxst.
#
# Brings up the remote-play stack (Sunshine + MoonDeck Buddy + Steam), hands the
# Steam Deck a dedicated virtual output to stream, and blanks the physical
# monitors so the desk is dark while the Deck plays.
#
# --- Migrated from Apollo to mainline Sunshine (2026-09-06) -----------------
#
# Apollo 0.4.8 aborts the instant a session starts on Wayland: its wlgrab
# backend never populates img->frame_timestamp, and encode_run() dereferences
# that empty std::optional. Arch builds with _GLIBCXX_ASSERTIONS so it is a
# hard SIGABRT, which Moonlight reports as "connection terminated, error -1".
# Apollo 0.4.6 has identical code, so downgrading does not help. Mainline
# Sunshine fixed both halves upstream (commit #4787 sets the timestamp from
# Wayland's ready timestamp; PR #5030 fixed wlr capture), shipped in
# 2026.516.143833. See ~/.local/src/apollo-patched/ for the patched Apollo
# build kept as a fallback.
#
# Called by modules/services/SteamDeckService.qml. Every subcommand is
# idempotent and safe to run twice: the QML side can retry without unwinding.
#
# --- Why a headless output rather than Apollo's virtual display -------------
#
# Apollo's per-client virtual display is Windows-only (it is built on SudoVDA,
# a Windows driver; upstream issue #1161). On Linux the compositor has to supply
# the display, and Hyprland's own `output create headless` is the supported way.
#
# The catch that drives the ordering below: a Hyprland headless output is NOT a
# DRM connector, so the KMS capture backend cannot see it. Sunshine captures it
# over zwlr_screencopy, selecting it by wl_output name - which means the output
# must EXIST BEFORE Sunshine starts, and the config must name it.
#
# So `up` creates the output FIRST and only then starts Sunshine, and `down`
# stops Sunshine BEFORE removing it. That ordering is the whole reason the
# output can be ephemeral at all -- nothing but this script starts the host
# (the unit is disabled, not enabled), so there is never a running Sunshine to
# strand on a display that just disappeared.
#
# The name is a FIXED constant rather than Hyprland's auto-assigned HEADLESS-N,
# so `output_name = sunshine` in sunshine.conf is written once and never
# churned. hyprland.lua carries a matching monitor rule -- inert while the
# output is absent -- so a `hyprctl reload` mid-mode reapplies the right
# mode/position instead of dropping it through the catch-all. This replaces the
# old create-HEADLESS-N -> read-back-its-index -> restart dance, which existed
# only because Apollo matched the output by ENUMERATION INDEX, not by name.
#
# --- Why the lua dispatch form ---------------------------------------------
#
# /usr/bin/hyprctl here is the lua-parser build: `hyprctl keyword` is refused
# outright and dispatchers are reached as `hl.dsp.*`. Dispatcher arguments must
# be POSITIONAL - `hl.dsp.dpms("off", "DP-1")`. The named-key form
# `hl.dsp.dpms({ state = "off", monitor = "DP-1" })` returns "ok" and silently
# TOGGLES instead of setting, which reads as success and is not.
#
# Note also that `hl.dsp.*` only builds a dispatcher object; `hyprctl dispatch`
# wraps its argument in `hl.dispatch(...)` to actually fire it. `hyprctl eval`
# does not, so an eval'd dispatcher is a no-op.

set -uo pipefail

# Deck native panel. The Deck's own client can request something else; this is
# just the mode the output is created at.
DECK_MODE="${DECK_MODE:-1280x800@60}"

# Name of the headless output. Created on `up`, removed on `down` -- it exists
# only while Steamdeck Mode is on, so no phantom monitor sits in the layout
# during ordinary desktop use.
DECK_OUTPUT="${DECK_OUTPUT:-sunshine}"

# Parked far to the right of the physical layout (which spans x=0..10719 across
# DP-3, DP-1 and HDMI-A-1) so the virtual output can never overlap a real one
# and shuffle windows around. "auto" would risk exactly that.
DECK_POSITION="${DECK_POSITION:-12000x0}"

# Workspace bound to the virtual output. Must match the workspace_rule in
# hyprland.lua and the one ~/.local/bin/sunshine-stream-display focuses --
# all three have to agree or windows land on the desk instead.
DECK_WORKSPACE="${DECK_WORKSPACE:-11}"

SUNSHINE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.conf"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/ambxst-steamdeck"
OUTPUT_FILE="$STATE_DIR/output"

mkdir -p "$STATE_DIR"

log() { printf '[steamdeck-mode] %s\n' "$*" >&2; }

# --- helpers ---------------------------------------------------------------

# Names of every real monitor (everything Hyprland reports that is not one of
# our virtual outputs). Used so blanking never touches the Deck's display.
# Excludes BOTH the legacy HEADLESS-N names and our own "sunshine" output.
# Missing the latter is not cosmetic: `blank` would DPMS-off the very display
# being captured, and the Deck would stream a black screen.
physical_monitors() {
	hyprctl monitors -j |
		jq -r --arg deck "$DECK_OUTPUT" \
			'.[] | select((.name | startswith("HEADLESS-") | not) and .name != $deck) | .name'
}

all_monitor_names() {
	hyprctl monitors -j | jq -r '.[].name'
}

# The headless output we created, if it is still present.
current_output() {
	[ -f "$OUTPUT_FILE" ] || return 1
	local name
	name=$(cat "$OUTPUT_FILE")
	[ -n "$name" ] || return 1
	all_monitor_names | grep -qx "$name" || return 1
	printf '%s' "$name"
}

# dpms <on|off> <monitor-name>
#
# Uses axctl, NOT `hyprctl dispatch hl.dsp.dpms(...)`. The lua dispatcher
# IGNORES its state argument and unconditionally TOGGLES: calling
# hl.dsp.dpms("on", "DP-1") on a monitor that is already on turns it OFF.
# Verified 2026-09-06 by calling it three times in a row with the same "on"
# argument and watching the state flip false/true/false each time. Every
# argument spelling behaves this way - positional, table, and named-key - so
# there is no correct incantation, only a different dispatcher.
#
# `axctl monitor set-dpms <id> <0|1>` is a real setter and is idempotent, which
# is what every caller here relies on.
dpms() {
	local state="$1" name="$2" id
	id=$(axctl monitor list 2>/dev/null | jq -r --arg n "$name" '.[]|select(.name==$n)|.id')
	[ -n "$id" ] || return 1
	axctl monitor set-dpms "$id" "$([ "$state" = on ] && echo 1 || echo 0)" >/dev/null 2>&1
}

# --- steam -----------------------------------------------------------------

# Started if absent, never stopped again on the way out - Harrison's call, and
# the right one: Steam is slow to start and harmless to leave running.
#
# `pgrep -x steam` matches the real client process (…/ubuntu12_32/steam), not
# the launcher script or the webhelper. Millennium injects into that same
# process, so its presence changes nothing here.
ensure_steam() {
	if pgrep -x steam >/dev/null 2>&1; then
		log "steam already running"
		return 0
	fi
	log "starting steam (-silent: the displays are about to go dark anyway)"
	setsid -f steam -silent >/dev/null 2>&1
}

# --- virtual output --------------------------------------------------------

# Created here on the way up, removed by remove_output on the way down, so the
# virtual display exists only while the mode is on.
#
# Idempotent on purpose: a re-entry, or a session where teardown was skipped,
# finds it already present and just re-pins its geometry.
ensure_output() {
	if all_monitor_names | grep -qx "$DECK_OUTPUT"; then
		log "virtual output $DECK_OUTPUT present"
	else
		hyprctl output create headless "$DECK_OUTPUT" >/dev/null 2>&1
		sleep 0.5
		if ! all_monitor_names | grep -qx "$DECK_OUTPUT"; then
			log "ERROR: could not create output $DECK_OUTPUT"
			return 1
		fi
		log "created virtual output $DECK_OUTPUT"
	fi
	printf '%s' "$DECK_OUTPUT" >"$OUTPUT_FILE"
	reassert_output
}

# Re-assert mode, position and workspace binding. hyprland.lua carries a
# matching rule so a `hyprctl reload` reapplies the right values, but this stays
# because it is cheap, idempotent, and covers the window between `output create`
# (which lands at 1920x1080 @auto) and the rule taking effect.
reassert_output() {
	all_monitor_names | grep -qx "$DECK_OUTPUT" || return 1
	hyprctl eval "return hl.monitor({ output = \"$DECK_OUTPUT\", mode = \"$DECK_MODE\", position = \"$DECK_POSITION\", scale = 1 })" >/dev/null 2>&1
	hyprctl eval "return hl.workspace_rule({ workspace = \"$DECK_WORKSPACE\", monitor = \"$DECK_OUTPUT\", default = true })" >/dev/null 2>&1
}

# Remove the virtual output. MUST run after stop_sunshine: Sunshine resolves
# output_name once at startup, so pulling the display out from under a running
# host leaves it capturing a monitor that no longer exists.
#
# output_name in sunshine.conf is deliberately left naming "sunshine" -- the
# next `up` recreates the output under the same name before the host starts.
# Clearing it to 0 here is exactly what used to repoint the stream at DP-1.
#
# Any window still parked on workspace $DECK_WORKSPACE is moved by Hyprland to a
# remaining monitor when the output goes; nothing is lost, it just reappears on
# the desk. That is why `down` runs after games are expected closed.
remove_output() {
	if all_monitor_names | grep -qx "$DECK_OUTPUT"; then
		hyprctl output remove "$DECK_OUTPUT" >/dev/null 2>&1
		log "removed virtual output $DECK_OUTPUT"
	fi
	rm -f "$OUTPUT_FILE"
}

# --- sunshine --------------------------------------------------------------

SUNSHINE_LOG="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.log"

# Set one key in sunshine.conf, leaving every other setting Harrison may have
# set through the web UI untouched.
set_sunshine_key() {
	local key="$1" value="$2" tmp
	mkdir -p "$(dirname "$SUNSHINE_CONF")"
	touch "$SUNSHINE_CONF"
	tmp=$(mktemp)
	grep -v "^${key}[[:space:]]*=" "$SUNSHINE_CONF" >"$tmp" 2>/dev/null
	printf '%s = %s\n' "$key" "$value" >>"$tmp"
	mv "$tmp" "$SUNSHINE_CONF"
	chmod 600 "$SUNSHINE_CONF"
}

# Mainline Sunshine matches output_name against the wl_output NAME, so this is
# written once to the constant and never recomputed.
#
# Apollo matched on the ENUMERATION INDEX instead, which is why this used to
# start the host, parse the index out of its log, rewrite the config and
# restart -- and why teardown reset output_name to 0. That reset is what
# silently repointed Sunshine at DP-1 after a Steamdeck Mode exit.
ensure_output_name() {
	grep -qx "output_name = $DECK_OUTPUT" "$SUNSHINE_CONF" 2>/dev/null && return 0
	set_sunshine_key output_name "$DECK_OUTPUT"
	log "sunshine output_name = $DECK_OUTPUT"
}

# Sunshine writes its monitor list a second or two after start. Poll rather than
# sleeping a guessed constant.
sunshine_wait_for_enumeration() {
	local i
	for i in $(seq 1 40); do
		grep -q "End of Wayland monitor list" "$SUNSHINE_LOG" 2>/dev/null && return 0
		sleep 0.5
	done
	log "WARNING: timed out waiting for Sunshine to enumerate monitors"
	return 1
}

start_sunshine() {
	systemctl --user start "$SUNSHINE_UNIT"
	log "sunshine started"
	sunshine_wait_for_enumeration
}

stop_sunshine() {
	systemctl --user stop "$SUNSHINE_UNIT" 2>/dev/null
	log "sunshine stopped"
}

# --- moondeck buddy --------------------------------------------------------
#
# Run as a transient unit rather than a bare background process so it can be
# stopped reliably by name, and so a crash cannot leave an orphan holding the
# Steam pipe. The AppImage's own autostart units are deliberately not used:
# those are for always-on operation, and this stack is meant to be off by
# default.

# Must be exactly "moondeckbuddy.service": Buddy looks itself up by that unit
# name (`buddy.os: Service unit "moondeckbuddy.service" does not exist.` in its
# debug log when it cannot find it). Running it as a transient unit under a
# different name left Buddy unable to see its own service. The unit lives in
# ~/.config/systemd/user and is deliberately NOT enabled - Steamdeck Mode starts
# and stops it, so the stack stays off by default.
MOONDECK_UNIT=moondeckbuddy.service

start_moondeck() {
	if systemctl --user is-active --quiet "$MOONDECK_UNIT"; then
		log "moondeck buddy already running"
		return 0
	fi
	systemctl --user start "$MOONDECK_UNIT"
	log "moondeck buddy started"
}

stop_moondeck() {
	systemctl --user stop "$MOONDECK_UNIT" 2>/dev/null
	log "moondeck buddy stopped"
}

# --- subcommands -----------------------------------------------------------

case "${1:-}" in
# Bring the stack up. Deliberately does NOT blank anything: an accidental
# button press should be undoable before the desk goes dark, so QML holds a
# grace period and calls `blank` separately.
up)
	ensure_steam
	ensure_output || exit 1
	ensure_output_name
	start_sunshine
	start_moondeck
	;;

# Blank the real monitors, leaving the Deck's virtual output live.
blank)
	for m in $(physical_monitors); do
		dpms off "$m"
	done
	log "physical monitors blanked"
	;;

# Wake the real monitors. Driven by SteamDeckService's IdleMonitor on input,
# and idempotent so it can be fired on every wake without checking first.
wake)
	for m in $(physical_monitors); do
		dpms on "$m"
	done
	;;

# Tear the stack down. Steam is intentionally left running.
#
# No shell reload is needed after this any more. Removing an output used to
# leave the bar mis-reserved (and, with it, quickshell burning GPU in a render
# loop), because the shell unregistered the WRONG screen on teardown --
# Quickshell hands a dying window's `screen` to a surviving output, so the
# panel being destroyed named a live monitor. Fixed 2026-09-06 in
# Visibilities/UnifiedShellPanel; verified over repeated create/remove cycles
# of this very output with the reservation and GPU both staying flat.
#
# `steamdeck-mode-rescue` still restarts the shell, for the different job of
# clearing a stuck lock overlay.
down)
	stop_sunshine
	stop_moondeck
	for m in $(physical_monitors); do
		dpms on "$m"
	done

	# Only now, with the host stopped, is it safe to pull the display.
	# output_name stays pointed at "sunshine": `up` recreates the output under
	# that same name before Sunshine starts again.
	remove_output
	;;

# Move focus onto the Deck's workspace so anything Steam launches opens there.
# Called once the lock is up, never while Harrison is using the desk - focus on
# an invisible output means his keystrokes go somewhere he cannot see.
focus-deck)
	reassert_output
	hyprctl dispatch "hl.dsp.focus({ workspace = $DECK_WORKSPACE })" >/dev/null 2>&1
	log "focus -> workspace $DECK_WORKSPACE (deck)"
	;;

# Hand focus back to the physical desk.
focus-desk)
	target=$(physical_monitors | head -1)
	[ -n "$target" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$target\" })" >/dev/null 2>&1
	log "focus -> $target (desk)"
	;;

status)
	printf 'sunshine:  %s\n' "$(systemctl --user is-active "$SUNSHINE_UNIT" 2>/dev/null)"
	printf 'moondeck:  %s\n' "$(systemctl --user is-active "$MOONDECK_UNIT" 2>/dev/null)"
	printf 'steam:     %s\n' "$(pgrep -x steam >/dev/null && echo running || echo stopped)"
	printf 'output:    %s\n' "$(current_output || echo none)"
	printf 'monitors:  %s\n' "$(all_monitor_names | tr '\n' ' ')"
	;;

*)
	echo "usage: ${0##*/} {up|down|blank|wake|status}" >&2
	exit 1
	;;
esac
