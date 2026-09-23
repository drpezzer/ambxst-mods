# Live Notifications

Notifications that replace themselves now update in place.

The desktop notification protocol lets an app re-send a notification with the
ID it was given (`notify-send -r ID`, or `replaces_id` over D-Bus). That is how
downloaders, copy dialogs and music players show a percentage that moves
without piling up a new bubble on every tick. Stock Ambxst copies a
notification's summary, body, icon and image once, the moment it arrives, and
never looks at the object again, so a replaced notification keeps showing its
first text in the notch and in the history.

## What changes

- Summary, body, urgency, actions, icon and image follow every replacement.
- A replaced notification that had already timed out pops back up, with a fresh
  timer taken from the new message (`-t 0` still means "stay until closed").
- The history entry is refreshed and moves to the top, rather than being
  duplicated.
- `CloseNotification` (`gdbus ... CloseNotification ID`) already removed the
  bubble; that is unchanged.

Nothing else is touched. One patch on `modules/services/Notifications.qml`,
insertions only.

## Try it

```bash
id=$(notify-send -p -t 0 "Copying" "0%")
for p in 25 50 75 100; do sleep 1; notify-send -r "$id" -t 0 "Copying" "$p%"; done
gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification "$id"
```

## Changelog

- 1.0.0 (2026-09-22): first release, on Ambxst 1.3.8 (2a704c43).
