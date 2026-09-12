# Multi-monitor fixes

Monitor hotplug without an `ambxst reload`, and a few multi-screen state bugs.

- **Unplugging a monitor no longer breaks a surviving one.** When an output
  goes away, Quickshell reassigns the dying panel window's `screen` to a
  surviving output, so a panel that unregistered itself by `screen.name` at
  teardown was deleting a *live* screen's entry from the visibility registry
  and leaving the dead one behind. The survivor then had no bar, dock or
  notch panel to resolve its reveal and pinned state from, which is the
  "windows spill under the bar until reload" symptom. Panels now latch the
  name they registered under at creation and unregister by that, and the
  registry ignores an unregister that doesn't come from the registered owner.
- **The wallpaper manager survives losing its screen.** One Wallpaper instance
  owns scanning, matugen and thumbnails for the whole shell. If its monitor was
  unplugged that role died with it and every other screen kept a wallpaper it
  could no longer rescan or re-theme. The role is now handed to a surviving
  instance, carrying the current state across so nothing blanks.
- **No more invisible view stuck in the notch.** Moving an open module to the
  newly focused monitor could set and clear a screen's flag inside one event
  loop turn, leaving a deferred push behind that parked a hidden 900 px view
  in the notch. The push re-checks the flag and the close unwinds the stack.
- **Fullscreen games on a special workspace are detected.** The panel only
  caught them through a fast path gated on the focused monitor, so the shell
  came back over the game whenever focus moved. The output's open special
  workspace is now read from Hyprland and checked too.
- **No dead strip where a hidden bar used to be.** Going fullscreen hides the
  bar, the dock and the frame, but their layer-shell exclusive zones stayed
  put, so every window below kept a gap against that screen edge. The
  reservation now follows the chrome, screen for screen.
- **The bar stays away from the screen the fullscreen window is on.** The bar
  and dock read fullscreen off the *focused* toplevel, so both came straight
  back the moment focus moved to another monitor -- over a game that was still
  fullscreen, and dragging that screen's windows back off the edge with them.
  Each screen's own fullscreen state is now ORed in, the same per-output check
  the notch and frame already use, so the screen holding the fullscreen window
  keeps its chrome away until that window is gone while the other screens get
  theirs back on the next focus change.
- **Null guards** on about fifteen `screen.name` bindings that threw a
  `TypeError` cascade during teardown.

## Install

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/multi-monitor-fixes
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/multi-monitor-fixes
ambxst mods enable drpezzer.multi-monitor-fixes
ambxst reload
```

## What it changes

One patch, thirteen files: `Bar.qml`, `BarContent.qml`, `DockContent.qml`,
`ScreenFrameContent.qml`, `NotchContent.qml`, `NotchWindow.qml`,
`Visibilities.qml`, `GlobalStates.qml`, `UnifiedShellPanel.qml`,
`Wallpaper.qml`, `OverviewPopup.qml`, `PresetsPopup.qml`, `shell.qml`. No new
files, no new config keys. Reads Hyprland monitor state through
`Quickshell.Hyprland` for the special-workspace check.

Testing hotplug without real hardware: `hyprctl output create headless` and
`hyprctl output remove HEADLESS-N` are faithful add/remove events.

Works with Ambxst `>=1.3.0`.

## Changelog

- **1.1.0** — a bar, dock or frame hidden by a fullscreen window no longer
  keeps its exclusive zone, so the windows below fill the space instead of
  leaving a gap at the screen edge; and the screen holding that window keeps
  its bar and dock hidden when focus moves away, instead of putting them back
  over a still-fullscreen window.
- **1.0.3** — verified on Ambxst 1.3.3 (base af9f8ad4); patch applies verbatim, no source changes.
- **1.0.2** — the Visibilities hunk no longer drops upstream 1.3's bar-popup
  grouping.

- **1.0.1** — re-ported the Wallpaper changes onto 1.3; 1.0.0's patch had
  carried the pre-1.3 helper-script calls into that file.
- **1.0.0** — first packaged release.
