# Caelestia Style Lockscreen

A port of [Caelestia](https://github.com/caelestia-dots/shell)'s lockscreen
into Ambxst, restyled to a minimal composition in Ambxst's own palette.

- The desktop is grabbed with `grim` an instant before the lock engages and
  blurred in, so the lock rises out of what you were looking at and settles
  back into it on unlock, instead of cutting to a wallpaper.
- A padlock animation in the style of Hypr-Prelock sweeps in first: rays,
  two closing rings, and a shackle that drops into the body.
- The password field is Caelestia's Material-shapes one: every typed character
  becomes a different shape and the submit button morphs from a circle to an
  arrow. That field is compiled C++ from the `M3Shapes` plugin, which is the
  whole reason this is a port and not a re-creation.
- Clock, date, avatar (`~/.face.icon`, as set from Ambxst's avatar picker), a
  fortune quote bottom-left, and a now-playing line up top. The vitals use
  Caelestia's compiled services, coloured to match Ambxst's metrics panel.
- The clock, date and quote decode into place as the composition reveals:
  each glyph cycles through katakana and settles left to right. It is a
  transition, not a tick; the clock's minute changes are plain.
- The clock follows Ambxst's own 12/24-hour setting (`bar.use12hFormat`).

Two new keys in `lockscreen.json`:

| Key | Default | Meaning |
|---|---|---|
| `screen` | `""` | Connector name the composition is drawn on, e.g. `"DP-1"`. Empty follows the focused monitor, which at boot is wherever the pointer happens to be. Ignored when that screen is unplugged. |
| `lockOnStart` | `false` | Lock once per compositor session as soon as the shell is ready. For setups that autologin without a password. |

## Requirements

- `grim` (declared; the build refuses without it).
- The `caelestia-shell` package, for its `M3Shapes` and `Caelestia.*` QML
  plugins on the system-wide Qt import path. It is only a library here and is
  never started. On Arch: `yay -S caelestia-shell`.
- `fortune` is optional; without it the quote is simply empty.

## Install

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/caelestia-lockscreen
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/caelestia-lockscreen
ambxst mods enable drpezzer.caelestia-lockscreen
ambxst reload
```

Then test with `ambxst lock`, or `qs -p <generation>/shell.qml ipc call lockscreen lock`
which locks without asking for a password on the way out.

## Changelog

- **1.1.2** — the scramble is a reveal transition only; real twelve-hour
  clock (Qt's `h` needs an am/pm token to be twelve-hour, so the string is
  built from the hour and minute values).
- **1.1.0** — katakana scramble on the clock, date and quote; the clock follows
  Ambxst's 12/24-hour setting; renamed to Caelestia Style Lockscreen.
- **1.0.0** — first packaged release.

## What it changes

- New: everything under `modules/lockscreen/cae/` (the ported lock modules,
  the Caelestia components and services they use, the pam.d configs, the
  fortune script).
- `shell.qml` — the `WlSessionLock` gets the ported surface, the desktop grab,
  the boot lock, and the imperative lock/unlock wiring (the unlock animation
  ends by writing `locked = false`, so it cannot be a binding).
- `config/Config.qml`, `config/defaults/lockscreen.js` — the two keys.
- `modules/components/CircularSeekBar.qml` — a hidden handle and a junction
  dot for the read-only vitals gauges.

The stock `modules/lockscreen/LockScreen.qml` stays in the tree, unused,
so disabling the mod puts it straight back.

Works with Ambxst `>=1.3.0`.
