# Settings Float

Opens the Ambxst Settings window as a centred floating window, sized to the
screen it opens on, instead of tiling it into whatever workspace is current.

## How it works

The stock `SettingsWindow.qml` already finds its own toplevel through the
compositor state and moves it to the target workspace. This mod adds one step
right after that: if the window is not floating it asks the compositor to float
it, then resizes and moves it to the centre of the screen it was opened on. All
three requests go through Ambxst's own compositor abstraction (`axctl`), the
same path the stock placement uses, so nothing has to be added to your Hyprland,
Niri or Mango config and it behaves the same on every distribution.

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

- Floating is only requested when the window opens. If you float or tile it
  yourself while it is open, the mod does not fight you.
- If you already have a compositor window rule for the Settings window, keep or
  drop it; the mod's resize and centre run after the rule and win.
- Centring uses the full screen area. A bar that reserves space shifts the
  visual centre by half the bar's thickness.

## Changelog

- 1.0.0: initial release, verified on Ambxst 1.3.3 (base af9f8ad4).
