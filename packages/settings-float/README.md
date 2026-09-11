# Settings Float

Opens the Ambxst Settings window as a centred floating window, sized to the
screen it opens on, instead of tiling it into whatever workspace is current.

## How it works

Until the compositor has placed it, the window declares a fixed size (minimum
equals maximum), derived from the screen it opens on. Compositors treat a
fixed-size toplevel like a dialog and float it the moment it maps, so it never
appears as a tile first and never reflows the workspace. Hyprland and Niri also
centre it on their own, keeping clear of bars. Once the stock placement code
sees the window in the compositor state, the constraints are released so you
can resize it by hand.

A small singleton (`SettingsFloatService`) holds the mod's settings from shell
start, because the window is created on open and its size has to be known
before it maps. Nothing is added to your compositor config.

The size is derived from the screen, in logical pixels, so HiDPI scaling is
handled by the compositor:

| | default |
|---|---|
| width | 41% of the screen, at least 900 px, at most 92% |
| height | 66% of the screen, at least 650 px, at most 92% |

On a 3440x1440 ultrawide that is 1410x950; on 1920x1080 it is 900x713; on a
1366x768 laptop panel it is 900x650.

## Settings

Under Settings > Mods > Settings Float:

- **Float the Settings window** (on by default). Off restores stock behaviour
  without disabling the mod.
- **Width / Height, percent of the screen.** The floor and ceiling above always
  apply.

Changes take effect the next time Settings is opened; no reload needed.

## Notes

- The hint only matters at map time. If you float or tile the window yourself
  while it is open, the mod does not fight you.
- A compositor that does not float fixed-size windows tiles it exactly as
  stock Ambxst does; add a rule for `org.quickshell` + title `Ambxst Settings`
  there. Hyprland, Niri and dwl-based compositors honour the hint.
- There is deliberately no "float it through the compositor" fallback: Ambxst's
  compositor state reports a window floated at map as not floating, and acting
  on that flag tiled the window it was meant to float.
- Settings edits apply on the next open; a setting changed while the panel is
  open is picked up live.

## Changelog

- 1.1.0: float at map time via a fixed-size hint (no more tile-then-float flash); settings held in a startup singleton; constraints released after placement so the window stays resizable; the compositor-state fallback from 1.0.0 is gone (it mis-tiled the window).
- 1.0.0: initial release, verified on Ambxst 1.3.3 (base af9f8ad4).
