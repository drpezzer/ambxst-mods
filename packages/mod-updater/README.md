# Mod Updater

Update checking for Settings > Mods.

- **Check for updates** sits next to the installed-mods search box. It asks each
  installed mod's source for its current manifest and compares versions. With
  nothing newer it reads *No updates* for a moment, then fades back.
- When newer versions exist the same button becomes **Install N updates**, and
  every mod with an update gets its own **Update to x.y.z** button next to
  Enable/Disable. Installs go through the mod manager's normal update path, so
  each one rebuilds the generation and the usual "Restart Ambxst" banner and
  rollback apply.
- Two switches under *Bypass Ambxst version check*:
  - **Check for mod updates automatically**: about 90 seconds after the shell
    starts, and then every few hours (interval configurable in the mod's own
    settings, default 6 h), the shell checks in the background. If anything is
    newer you get a notification with *Open Mods*, *Later* (snoozes 8 h) and
    *Update all*.
  - **Install mod updates automatically**: what an automatic check finds is
    installed right away, followed by a notification with a *Restart now*
    button. The shell never restarts itself.

## How versions are checked

| Source type | Where the latest version comes from |
|---|---|
| local directory | `ambxst.mod.json` in the source directory |
| git clone (plain Git URL) | `git fetch` in the package clone, manifest read from the fetched head |
| GitHub tree URL (`…/tree/<ref>/<dir>`) | the manifest fetched from raw.githubusercontent.com, no clone needed |
| archive | cannot be checked |

Only the version field decides; a source that changed without bumping its
version does not show as an update. Versions are compared as dotted numbers
(`1.2.10` is newer than `1.2.9`); non-numeric versions count as an update when
they differ.

## Files

- `modules/services/ModUpdateService.qml` (new): check/install state machine,
  scheduling, notifications.
- `modules/services/mod_update_check.sh` (new): the per-source checker; prints
  `id<TAB>version` or `id<TAB>ERR:reason` per mod.
- `modules/widgets/dashboard/controls/ModsPanel.qml`: the button, the per-mod
  Update buttons, the two switches, and their English strings (pure insertions).
- `shell.qml`: one line that instantiates the service at boot so automatic
  checks run without the panel being open.

Requires `git` and `curl`, both of which Ambxst already uses.

## Changelog

- 1.0.1: the button itself reports "No updates" and crossfades back; no banner message.
- 1.0.0: initial release.
