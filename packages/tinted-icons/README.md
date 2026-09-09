# Tinted icons

Makes Ambxst's *Tint Icons* retheme app icons instead of filtering them.
Icons in the tray, dock, workspace pills and launcher are mapped through a
lightness ramp built from your theme's primary family, so every icon lands in
one hue with its own shading intact: gradients stay gradients, greys stay
neutral, and the whole set follows whatever matugen generated from your
wallpaper. The active workspace and the selected launcher entry swap to the
primary colour.

A **True Monochrome** switch under *Settings → Theme → Tint Icons* flattens
icons to a single colour instead. It only does anything while *Tint Icons* is
on, and it is off by default.

<img src="assets/comparison.png" alt="Default ramp tint, True Monochrome, and the original icons">

<p>
<img src="assets/bar.png" alt="Bar with tinted app icons" height="320">
&nbsp;&nbsp;
<img src="assets/dock.png" alt="Dock with tinted app icons">
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

## How the recolouring works

The shader is a port of the colour mapping in
[Iconicul](https://codeberg.org/dvrkxed/iconicul) by dvrkxed (MIT), which
recolours whole icon themes on disk. Each pixel is converted to Lab, its
lightness is remapped onto the ramp's lightness range, the ramp anchors are
blended with a Gaussian window, and the result's chroma is scaled by how
saturated the source pixel was, so anti-aliased greys stay quiet. The ramp is
`background → primaryContainer → inversePrimary → primary → primaryFixed`.

Stock *Tint Icons* blends the whole 26-colour palette by RGB distance, which
posterises multicolour icons. Feeding a lightness mapping the whole palette
does not help either: matugen's accents share a lightness band, so they
average out into beige. Restricting the ramp to the primary family is what
makes it read as a retheme.

## What it changes

- New: `modules/components/icon_ramp_tint.frag` and its compiled `.qsb`.
- `modules/components/Tinted.qml` — the ramp palette, the new shader, and the
  `monochrome` / `tintColor` properties. The existing `fullTint`, which the
  launcher logo uses, is untouched.
- `config/Config.qml`, `config/defaults/theme.js` — the `theme.trueMonochromeTint` key.
- `modules/widgets/dashboard/controls/ThemePanel.qml` — the switch.
- `modules/globals/GlobalStates.qml` — the key joins the theme snapshot list.
- `SysTrayItem.qml`, `DockAppButton.qml`, `Workspaces.qml`, `LauncherView.qml`
  — pass the switch and the per-state colour into `Tinted`.

Works with Ambxst `>=1.3.0`.

## Changelog

- **2.0.0** — the tint is now a primary-family lightness ramp (Iconicul's
  method); the flat single-colour mode moved behind a *True Monochrome* switch.
- **1.2.0** — monochrome only, no switch.
- **1.1.0** — restored the stock `fullTint`, which 1.0.0 had changed and which
  turned a dark launcher logo black. Thanks to Axenide for the report.
- **1.0.0** — first release.
