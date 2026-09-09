# Tinted icons

Adds a **Monochrome Tint** switch to *Settings → Theme*, right under *Tint
Icons*. With it on, tinted app icons in the tray, dock, workspace pills and
launcher are drawn in a single theme colour while keeping their own shading,
so the glyphs stay readable and everything follows whatever matugen generated
from your wallpaper. The active workspace and the selected launcher entry swap
to the primary colour.

Stock Ambxst's *Tint Icons* remaps each icon's palette to the theme instead.
This is a matter of taste, so both stay available: the new switch only does
something while *Tint Icons* is on, and it is off by default.

<p>
<img src="assets/bar.png" alt="Bar with monochrome tinted app icons" height="320">
&nbsp;&nbsp;
<img src="assets/dock.png" alt="Dock with monochrome tinted app icons">
</p>

## Install

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
ambxst mods enable drpezzer.tinted-icons
ambxst reload
```

Then turn on *Settings → Theme → Tint Icons* and *Monochrome Tint*.

## What it changes

One patch, eight files:

- `modules/components/Tinted.qml` — new `monochrome` and `tintColor` properties.
  The existing `fullTint` (used by the launcher logo) is untouched.
- `config/Config.qml`, `config/defaults/theme.js` — the `theme.monochromeTint` key.
- `modules/widgets/dashboard/controls/ThemePanel.qml` — the switch, disabled while
  *Tint Icons* is off.
- `modules/globals/GlobalStates.qml` — the key joins the theme snapshot list so
  Revert in Settings covers it.
- `modules/bar/systray/SysTrayItem.qml`, `modules/dock/DockAppButton.qml`,
  `modules/bar/workspaces/Workspaces.qml`, `modules/widgets/launcher/LauncherView.qml`
  — pass the switch and the per-state colour into `Tinted`.

Works with Ambxst `>=1.3.0`.

## Changelog

- **1.1.0** — Monochrome tint is a switch instead of always-on, following
  feedback from Axenide. Fixes the launcher logo turning black, which happened
  because 1.0.0 changed the meaning of the stock `fullTint`.
- **1.0.0** — first release.
