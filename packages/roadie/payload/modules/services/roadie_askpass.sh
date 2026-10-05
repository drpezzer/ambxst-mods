#!/bin/sh
# Ambxst Roadie (drpezzer.roadie): sudo's askpass helper for a command run from
# the AI sidebar (roadie_sudo_run.sh). There is no terminal for sudo to ask for
# the password on, so it runs this and reads the password from its output.
#
# The password typed into the sidebar's box comes through the pipe the runner
# holds open. It gives one answer while the password is being checked; a second
# question then means the first answer was wrong, and waiting here until the
# timeout makes sudo give up instead of trying it again.
if [ -n "$ROADIE_ASKPASS_FIFO" ] && [ -p "$ROADIE_ASKPASS_FIFO" ]; then
    # One line: the runner may have written the answer twice by the time it is read.
    exec timeout 2 head -n 1 "$ROADIE_ASKPASS_FIFO"
fi

# No password was typed (sudo did not need one when asked, and does now):
# a dialog, whichever this machine has.
prompt="${1:-Password:}"
if command -v zenity >/dev/null 2>&1; then
    exec zenity --password --title="Run as root" 2>/dev/null
fi
if command -v kdialog >/dev/null 2>&1; then
    exec kdialog --title "Run as root" --password "$prompt" 2>/dev/null
fi
for helper in /usr/bin/ksshaskpass /usr/lib/ssh/ssh-askpass /usr/lib/ssh/x11-ssh-askpass \
    /usr/lib/openssh/gnome-ssh-askpass /usr/libexec/openssh/gnome-ssh-askpass \
    /usr/bin/lxqt-openssh-askpass /usr/lib/seahorse/ssh-askpass; do
    if [ -x "$helper" ]; then
        exec "$helper" "$prompt"
    fi
done
exit 1
