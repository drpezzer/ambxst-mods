# Tinted icons

With this mod on, Ambxst's *Tint Icons* draws app icons in the tray, dock,
workspace pills and launcher as single-colour glyphs that keep their own
shading, so the glyphs stay readable and everything follows whatever matugen
generated from your wallpaper. The active workspace and the selected launcher
entry swap to the primary colour.

Stock *Tint Icons* remaps each icon's palette to the nearest theme colours
instead, which posterises multicolour icons. This mod replaces that for app
icons and leaves everything else alone; turn *Tint Icons* off and icons are
stock again.

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

Then make sure *Settings → Theme → Tint Icons* is on.

## What it changes

One patch, five files:

- `modules/components/Tinted.qml` — new `monochrome` and `tintColor` properties.
  The existing `fullTint`, which the launcher logo uses, is untouched.
- `modules/bar/systray/SysTrayItem.qml`, `modules/dock/DockAppButton.qml`,
  `modules/bar/workspaces/Workspaces.qml`, `modules/widgets/launcher/LauncherView.qml`
  — switch to the monochrome mode and pass the per-state colour.

No new config keys. Works with Ambxst `>=1.3.0`.

## Changelog

- **1.2.0** — no separate switch; the mod is the monochrome mode.
- **1.1.0** — restored the stock `fullTint`, which 1.0.0 had changed and which
  turned a dark launcher logo black. Thanks to Axenide for the report.
- **1.0.0** — first release.
