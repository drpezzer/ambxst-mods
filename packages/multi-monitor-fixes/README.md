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
  workspace is now read from Hyprland and matched in the window scan as well
  as its active workspace, so the detection no longer depends on focus. That
  fast path is gone altogether: it ANDed the focused toplevel (Wayland) with
  the focused monitor (axctl), two sources that update independently, so on
  every swap away from a fullscreen window the *other* screen briefly believed
  it had one -- its bar pulled out and back and its frame blinked away.
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
  theirs back on the next focus change. On that screen the pointer does not
  bring them back either: sweeping the cursor off the game towards the next
  monitor crosses the bar's edge, which flashed it up over the game for the
  hide delay. `bar.availableOnFullscreen` keeps its meaning on the screens
  that are only hiding in sympathy, and a notch the user deliberately opens
  still reveals the bar. On that screen the hide is instant -- bar, exclusive
  zone and frame gutter drop in the frame the window arrives -- since the
  window is already fading in over them and a slower hide could be caught on
  top of a game opened and closed quickly.
- **The windows move with the bar.** When the bar slides away for a
  fullscreen window its exclusive zone is released and the compositor moves
  the windows into the space with its own resize animation -- on Hyprland
  `windowsMove`, which Ambxst sets to 250 ms, so the windows arrived first and
  the bar trailed in. For the length of a slide `windowsMove` is retuned to
  near-instant, and the exclusive zone is walked frame by frame along the
  bar's own slide instead of being switched, so the compositor lays the
  windows out against a value that moves with the pills and the frame slab
  -- one number, committed in the same frame, rather than two animations
  started a frame apart -- then restored once things are quiet. The restore
  re-reads Hyprland first and only writes the originals back if `windowsMove`
  still carries this mod's curve; the originals are also kept on disk so a
  shell killed mid-slide is put right by the next one. Hyprland only.
- **Hiding or showing the special workspace is followed instantly.** The
  screen's open special workspace is tracked from Hyprland's own
  `activespecial` event rather than read back from Quickshell's monitor
  object, which does not refresh on that event and whose refresh, when
  requested, could be folded into one already in flight with a stale reply.
  Before, the bar sometimes stayed away from a screen showing ordinary
  windows again, or the frame and bar stayed over a game that had just come
  back.
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
`Wallpaper.qml`, `OverviewPopup.qml`, `PresetsPopup.qml`, `shell.qml`; plus
one new file, `modules/services/BarSlideSync.qml`, the singleton that retunes
Hyprland's `windowsMove` during a bar slide. No new config keys. Reads
Hyprland monitor state through `Quickshell.Hyprland` for the
special-workspace check; on Hyprland runs `hyprctl eval` for the window
sync and keeps the original animation in
`~/.local/state/ambxst/multi-monitor-fixes-windowsmove.json` while tuned.

Testing hotplug without real hardware: `hyprctl output create headless` and
`hyprctl output remove HEADLESS-N` are faithful add/remove events.

### What the fullscreen slide assumes, and what it does not

- **Bar position** -- left, right, top or bottom; the slide travels along the
  bar's own axis by the exact size the exclusive zone changes by, which is
  computed from the bar's own target size, outer margin and frame allowance.
- **Screen size and scale** -- everything is in logical pixels on both sides
  (Quickshell and the compositor's reserved area), so HiDPI and mixed-scale
  setups need nothing special.
- **`theme.animDuration`** -- the slide is `1.6 x animDuration`; at `0` every
  animation is disabled and the shell behaves exactly as before.
- **An unpinned (auto-hide) bar** is left entirely to the stock auto-hide; the
  slide only ever engages for a bar that is holding space.
- **The screen the fullscreen window covers** hides its bar, zone and frame
  gutter instantly (there is nothing visible below to move in step with, and
  the window is already fading in over them); every other screen slides.
- **Compositor** -- the window-move sync (`BarSlideSync`) is Hyprland-only and
  runs `hyprctl eval`; on Niri or Mango it is inert and the slide still runs,
  with the compositor's own window animation. A `hyprctl` that hangs or is
  missing is given 250 ms, then the slide goes ahead without it.
- **Other mods** -- the retune is put back only if `windowsMove` still carries
  this mod's own curve, so a transition another mod has taken over (clean-load's
  shell enter/leave, for instance) is never yanked; the original is kept on
  disk so a shell killed mid-slide is restored by the next start.

Works with Ambxst `>=1.3.0`.

## Changelog

- **1.1.0** — a bar, dock or frame hidden by a fullscreen window no longer
  keeps its exclusive zone, so the windows below fill the space instead of
  leaving a gap at the screen edge; and the screen holding that window keeps
  its bar and dock hidden -- through focus changes and through the pointer --
  instead of putting them back over a still-fullscreen window. Fixes the
  special-workspace fullscreen check, which computed the output's open special
  workspace and then never compared anything against it, and drops the
  focused-monitor fast path that made the other screen's bar and frame blink
  on every swap. The bar's fullscreen hide is a clean-load-style slide -- full
  opacity, eased both ways, timed to land with the compositor's window move --
  and the frame's contain-bar slab follows that same travel; Hyprland's
  `windowsMove` is retuned to the slide for its duration so the windows move
  with the bar; and closing a special workspace refreshes the monitors so the
  bar comes back to that screen.
- **1.0.3** — verified on Ambxst 1.3.3 (base af9f8ad4); patch applies verbatim, no source changes.
- **1.0.2** — the Visibilities hunk no longer drops upstream 1.3's bar-popup
  grouping.

- **1.0.1** — re-ported the Wallpaper changes onto 1.3; 1.0.0's patch had
  carried the pre-1.3 helper-script calls into that file.
- **1.0.0** — first packaged release.
