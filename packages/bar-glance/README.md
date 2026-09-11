# Bar at a Glance

More of your system readable straight from the bar, without opening the apps
behind it.

- **Frame-attached popouts.** With *contain bar* on, the clock/calendar,
  audio and brightness controls, battery and power-profile picker, and the
  tiling layout switcher grow out of the frame like part of it instead of
  floating as separate pills. With *contain bar* off they stay floating pills,
  as stock.
- **Bluetooth in the bar.** An indicator that opens a frame-attached flyout on
  hover or click: adapter power, scanning, and connect, disconnect, pair, trust
  and forget per device. Right click opens `blueman-manager`. blueman's own
  tray icon is hidden so there is one Bluetooth icon in the bar; the new
  `bar.systrayExclude` list in bar.json controls that and takes any other
  tray ids you want gone.
  A second indicator shows the battery level of connected devices that report
  one (headsets, controllers, mice, keyboards).
- **Weather that knows it's night.** The bar's weather glyph switches to moon
  and night variants between sunset and sunrise instead of showing a sun at
  midnight.

## Install

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/bar-glance
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/bar-glance
ambxst mods enable drpezzer.bar-glance
ambxst reload
```

## How the popouts work

Ambxst draws the bar, notch and dock in one full-screen surface per monitor.
A popout that should merge with the frame has to be drawn in that same
surface, or the fill never joins and the frame's concave fillets can't overlap
it, so each widget hands its popout content to the panel as a `Component`
through `GlobalStates` and a single `BarFlyout` per screen instantiates it.
The new `BarPopout` component wraps that: widgets declare their content
inline as before, and it picks the attached or floating form from the
*contain bar* setting. Only one flyout is open at a time, shell-wide, and a
click anywhere outside it closes it.

## What it changes

- New: `modules/components/BarPopout.qml`, `modules/shell/BarFlyout.qml`,
  `modules/bar/BluetoothIndicator.qml`, `BluetoothFlyout.qml`,
  `BluetoothDeviceRow.qml`, `BluetoothBatteryIndicator.qml`,
  `modules/services/BluetoothControl.qml`, `BluetoothBattery.qml`.
- `modules/bar/clock/Clock.qml`, `ControlsButton.qml`, `BatteryIndicator.qml`,
  `LayoutSelectorButton.qml` — popouts move from `BarPopup` to `BarPopout`.
- `modules/bar/BarContent.qml` — the two Bluetooth indicators join the bar.
- `modules/bar/systray/SysTray.qml`, `config/Config.qml`, `config/defaults/bar.js`
  — the `bar.systrayExclude` filter, default `["blueman"]`.
- `modules/services/BluetoothDevice.qml`, `BluetoothService.qml` — pairing,
  trust and battery plumbing.
- `modules/services/WeatherService.qml` — day/night glyph selection on its own
  timer, since the sun-position timer only runs while a panel is open.
- `modules/globals/GlobalStates.qml`, `modules/shell/UnifiedShellPanel.qml`,
  `modules/theme/Icons.qml` — flyout state, the flyout surfaces and their
  input regions, and the Bluetooth device/battery glyph maps. Insertions only.

Works with Ambxst `>=1.3.0`. One new config key: `bar.systrayExclude`.

## Changelog

- 1.1.1: verified on Ambxst 1.3.3 (base af9f8ad4); patch applies verbatim, no source changes.
