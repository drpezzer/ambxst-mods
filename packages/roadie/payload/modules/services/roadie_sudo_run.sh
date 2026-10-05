#!/bin/bash
# Ambxst Roadie (drpezzer.roadie): runs a command the user approved in the AI
# sidebar's sudo box (RoadieSudo.qml).
#
#   roadie_sudo_run.sh check|plain <command>
#
# The command is run as written, by bash, with no terminal: sudo inside it gets
# the password from roadie_askpass.sh. With "check" the password typed into the
# box arrives as the first line of stdin. It is never in an argument, in the
# environment or in a file: it stays in this shell's memory and is handed to
# sudo's askpass through a pipe only this user can open, for as long as the
# command runs.
#
# The password is tried ONCE before anything runs. sudo would otherwise ask
# again after a wrong one, be given the same wrong one, and three failures can
# lock the account for ten minutes (pam_faillock). Exit status 77 = it was not
# accepted, nothing was run.
mode=$1
command=$2
here=$(dirname "$(readlink -f "$0")")

password=
if [ "$mode" = check ]; then
    IFS= read -r password
fi
exec </dev/null

export SUDO_ASKPASS="$here/roadie_askpass.sh"
fifo=
server=
child=

cleanup() {
    [ -n "$server" ] && kill "$server" 2>/dev/null
    [ -n "$fifo" ] && rm -f "$fifo"
    password=
}
trap cleanup EXIT
# Stop: end the command's shell and everything it started (it has a process
# group of its own). What already runs as root cannot be signalled from here
# and ends when it next writes to the closed pipe.
trap '[ -n "$child" ] && kill -- "-$child" 2>/dev/null; exit 143' TERM INT HUP

if [ "$mode" = check ]; then
    fifo=$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/roadie-askpass-XXXXXXXX")
    mkfifo -m 600 "$fifo" || exit 78
    export ROADIE_ASKPASS_FIFO="$fifo"

    # One answer, for the one try.
    (printf '%s\n' "$password" >"$fifo") &
    server=$!
    if ! sudo -A -v 2>/dev/null; then
        exit 77
    fi
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null

    # It is the right one: every sudo of the command may have it.
    (while :; do printf '%s\n' "$password" >"$fifo"; done) 2>/dev/null &
    server=$!
fi

setsid bash -c "$command" 2>&1 &
child=$!
wait "$child"
exit $?
