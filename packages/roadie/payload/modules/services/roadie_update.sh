#!/usr/bin/env bash
# Ambxst Roadie: update Ambxst and the mods that need the new version, in the
# one order that works.
#
#   roadie_update.sh --stage id[,id...] [--then id[,id...]] [--need X.Y.Z]
#
#   --stage  mods whose new version needs a newer Ambxst than the installed one
#   --then   other mods with an update waiting (installed after Ambxst)
#   --need   the lowest Ambxst version that satisfies every staged mod
#
# Why the order matters. The mod manager refuses a mod whose manifest asks for
# a newer Ambxst, so those cannot be installed first. Updating Ambxst first is
# no better: it rebuilds the mods that are installed, a mod written for the old
# version may no longer apply, one such mod fails the whole build, and Ambxst
# then starts without any mods at all. So:
#
#   1. the staged mods are disabled (the running shell is not restarted and
#      keeps them until the end) and their new versions fetched -- a disabled
#      mod is not checked against the Ambxst version;
#   2. Ambxst is updated by its own installer, the one `ambxst update` runs;
#   3. the staged mods are enabled again, now at their new versions, and the
#      other waiting updates are installed;
#   4. Ambxst restarts, once.
#
# Until step 2 has succeeded everything is put back as it was on any failure.
#
# Environment (for tests): ROADIE_UPDATE_INSTALLER (command run instead of the
# installer), ROADIE_UPDATE_YES=1 (no questions), ROADIE_UPDATE_NO_RESTART=1,
# ROADIE_UPDATE_AMBXST (the ambxst binary), ROADIE_UPDATE_KEEP_OPEN=0.
set -u

# Run from a private copy: the steps below rebuild the shell's generations,
# and this file lives in one.
if [ -z "${ROADIE_UPDATE_SELF:-}" ]; then
    self=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/roadie-update.XXXXXX") || exit 1
    cp -- "$0" "$self" || exit 1
    ROADIE_UPDATE_SELF=$self exec bash "$self" "$@"
fi
trap 'rm -f -- "$ROADIE_UPDATE_SELF"; [ -n "${LOCK:-}" ] && rmdir -- "$LOCK" 2>/dev/null' EXIT

STAGE=()
THEN=()
NEED=""
while [ $# -gt 0 ]; do
    case "$1" in
        --stage) IFS=',' read -r -a STAGE <<<"${2:-}"; shift 2 ;;
        --then)  IFS=',' read -r -a THEN <<<"${2:-}"; shift 2 ;;
        --need)  NEED=${2:-}; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

AMBXST=${ROADIE_UPDATE_AMBXST:-ambxst}
INSTALLER=${ROADIE_UPDATE_INSTALLER:-curl -fsSL get.axeni.de/ambxst | sh}
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/ambxst"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ambxst"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ambxst"
PACKAGES="$DATA/mods/packages"
STATE="$CONF/mods.json"
BASE="${AMBXST_SHELL:-$HOME/.local/src/ambxst}"

if [ -t 1 ]; then
    B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
    B=""; G=""; Y=""; R=""; D=""; N=""
fi
step() { printf '\n%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s    %s%s\n' "$Y" "$*" "$N"; }
bad()  { printf '%s    %s%s\n' "$R" "$*" "$N"; }

finish() {
    local code=$1
    if [ "${ROADIE_UPDATE_KEEP_OPEN:-1}" = "1" ] && [ -t 0 ]; then
        printf '\n%sPress Enter to close.%s ' "$D" "$N"
        read -r _ || true
    fi
    exit "$code"
}

# "1.3.10" >= "1.3.9"
ver_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

mods_list() { "$AMBXST" mods list 2>/dev/null; }
mod_field() { # id field(1 = state, 3 = version)
    mods_list | awk -v id="$1" -v f="$2" '$2 == id { print $f; exit }'
}

command -v "$AMBXST" >/dev/null 2>&1 || { bad "ambxst was not found in PATH."; finish 1; }

LOCK="${XDG_RUNTIME_DIR:-/tmp}/ambxst-roadie-update.lock"
if ! mkdir -- "$LOCK" 2>/dev/null; then
    LOCK=""
    bad "Another update is already running."
    finish 1
fi

# ── what is installed, what is out ──────────────────────────────────────────

if [ ! -d "$BASE/.git" ]; then
    bad "Ambxst at $BASE is not an installer checkout, so it cannot be updated from here."
    info "Update Ambxst the way you installed it, then update the mods from Settings > Mods."
    finish 1
fi
current=$(head -1 "$BASE/version" 2>/dev/null | tr -d '[:space:]')
branch=$(git -C "$BASE" rev-parse --abbrev-ref HEAD 2>/dev/null)
available=""
if [ -n "$branch" ] && [ "$branch" != "HEAD" ] && timeout 60 git -C "$BASE" fetch -q origin 2>/dev/null; then
    available=$(git -C "$BASE" show "origin/$branch:version" 2>/dev/null | head -1 | tr -d '[:space:]')
fi

declare -A WAS_ENABLED OLD_VERSION
for id in "${STAGE[@]}" "${THEN[@]}"; do
    [ -z "$id" ] && continue
    state=$(mod_field "$id" 1)
    if [ -z "$state" ]; then
        bad "$id is not installed."
        finish 1
    fi
    WAS_ENABLED[$id]=$([ "$state" = "enabled" ] && echo 1 || echo 0)
    OLD_VERSION[$id]=$(mod_field "$id" 3)
done

printf '%sUpdate Ambxst and its mods%s\n\n' "$B" "$N"
info "Ambxst installed: ${current:-unknown}"
info "Ambxst available: ${available:-unknown}"
[ -n "$NEED" ] && info "Needed by the mods below: $NEED or newer"
echo
for id in "${STAGE[@]}"; do [ -n "$id" ] && info "$id ${OLD_VERSION[$id]} -> its new version (needs the new Ambxst)"; done
for id in "${THEN[@]}";  do [ -n "$id" ] && info "$id ${OLD_VERSION[$id]} -> its new version"; done

if [ -n "$NEED" ] && [ -n "$available" ] && ! ver_ge "$available" "$NEED"; then
    echo
    bad "Ambxst $NEED is not out yet: an update would bring $available."
    info "Nothing was changed. The mods stay at their current versions until it is."
    finish 1
fi

if [ "${ROADIE_UPDATE_YES:-0}" != "1" ]; then
    echo
    info "Ambxst's installer asks for your password (it installs packages and the ambxst binary)."
    info "The shell restarts once, at the end."
    printf '\n    Proceed? [Y/n] '
    read -r answer || answer=n
    case "$answer" in
        ""|y|Y|yes|Yes) ;;
        *) info "Nothing was changed."; finish 0 ;;
    esac
fi

# ── 1. stage ────────────────────────────────────────────────────────────────

BACKUP="$CACHE/roadie-update-backup-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$BACKUP/packages" || { bad "Cannot write $BACKUP."; finish 1; }
cp -- "$STATE" "$BACKUP/mods.json" || { bad "Cannot read $STATE."; finish 1; }
for id in "${STAGE[@]}"; do
    [ -z "$id" ] && continue
    cp -a -- "$PACKAGES/$id" "$BACKUP/packages/$id" || { bad "Cannot back up $id."; finish 1; }
done

put_back() {
    step "Putting everything back"
    for id in "${STAGE[@]}"; do
        [ -z "$id" ] && continue
        [ -d "$BACKUP/packages/$id" ] || continue
        rm -rf -- "${PACKAGES:?}/$id"
        cp -a -- "$BACKUP/packages/$id" "$PACKAGES/$id"
    done
    cp -- "$BACKUP/mods.json" "$STATE"
    if out=$("$AMBXST" mods rebuild 2>&1); then
        info "Your mods are as they were. The shell was not restarted."
        rm -rf -- "$BACKUP"
    else
        bad "The mods could not be rebuilt: $out"
        info "The previous packages and mods.json are kept in $BACKUP"
    fi
}

step "Staging the mods that need the new Ambxst"
for id in "${STAGE[@]}"; do
    [ -z "$id" ] && continue
    if [ "${WAS_ENABLED[$id]}" = "1" ]; then
        if ! out=$("$AMBXST" mods disable "$id" 2>&1); then
            bad "$id could not be set aside: $out"
            put_back
            finish 1
        fi
    fi
done
for id in "${STAGE[@]}"; do
    [ -z "$id" ] && continue
    if ! out=$("$AMBXST" mods update "$id" 2>&1); then
        bad "$id: its new version could not be fetched: $out"
        put_back
        finish 1
    fi
    info "$id ${OLD_VERSION[$id]} -> $(mod_field "$id" 3)"
done

# ── 2. Ambxst ───────────────────────────────────────────────────────────────

step "Updating Ambxst"
if ! sh -c "$INSTALLER"; then
    bad "Ambxst's installer failed; Ambxst was not updated."
    put_back
    finish 1
fi
updated=$(head -1 "$BASE/version" 2>/dev/null | tr -d '[:space:]')
info "Ambxst is now ${updated:-unknown}"
if [ -n "$NEED" ] && [ -n "$updated" ] && ! ver_ge "$updated" "$NEED"; then
    bad "That is older than $NEED, which the staged mods need."
    put_back
    finish 1
fi

# ── 3. mods ─────────────────────────────────────────────────────────────────
# From here on there is no way back to the old Ambxst, so carry on past a
# failure and report it.

FAILED=()
step "Enabling the staged mods"
for id in "${STAGE[@]}"; do
    [ -z "$id" ] && continue
    if [ "${WAS_ENABLED[$id]}" != "1" ]; then
        info "$id stays disabled, as it was"
        continue
    fi
    if out=$("$AMBXST" mods enable "$id" 2>&1); then
        info "$id $(mod_field "$id" 3)"
    else
        bad "$id: $out"
        FAILED+=("$id")
    fi
done

if [ "${#THEN[@]}" -gt 0 ]; then
    step "Installing the other updates"
    for id in "${THEN[@]}"; do
        [ -z "$id" ] && continue
        if out=$("$AMBXST" mods update "$id" 2>&1); then
            info "$id ${OLD_VERSION[$id]} -> $(mod_field "$id" 3)"
        else
            bad "$id: $out"
            FAILED+=("$id")
        fi
    done
fi

step "Rebuilding the shell with its mods"
if out=$("$AMBXST" mods rebuild 2>&1); then
    info "done"
else
    bad "$out"
    warn "Ambxst will start WITHOUT mods until this is solved. A mod that is not ready for"
    warn "Ambxst ${updated:-the new version} is the usual cause: disable it in Settings > Mods, or"
    warn "with  ambxst mods disable <id>  and then  ambxst mods rebuild"
    FAILED+=("rebuild")
fi

# ── 4. restart ──────────────────────────────────────────────────────────────

if [ "${#FAILED[@]}" -eq 0 ]; then
    rm -rf -- "$BACKUP"
else
    echo
    warn "Not everything went through: ${FAILED[*]}"
    info "The previous packages are kept in $BACKUP"
fi

if [ "${ROADIE_UPDATE_NO_RESTART:-0}" != "1" ]; then
    step "Restarting Ambxst"
    "$AMBXST" reload >/dev/null 2>&1 || warn "Restart it with: ambxst reload"
fi

[ "${#FAILED[@]}" -eq 0 ] && printf '\n%sAll done.%s\n' "$G" "$N"
finish $([ "${#FAILED[@]}" -eq 0 ] && echo 0 || echo 1)
