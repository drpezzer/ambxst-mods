# ambxst-mods

Mods for [Ambxst](https://github.com/Axenide/Ambxst) 1.3+, packaged for its native
mod manager. Each folder under `packages/` is one installable package.

## Installing

Paste a package link into **Settings → Mods** and press *Install*:

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
```

Or from a terminal:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
ambxst mods enable drpezzer.tinted-icons
ambxst reload
```

Packages install disabled. Enabling shows the author, license and permissions,
builds a fresh source tree, and takes effect on the next `ambxst reload`. If
the shell fails to start within eight seconds Ambxst rolls back on its own.

## Packages

| Package | What it does |
|---|---|
| [tinted-icons](packages/tinted-icons) | Two switches under Tint Icons: True Matugen Icons (primary-family lightness ramp, Iconicul's method) and True Monochrome |
| [steamdeck-mode](packages/steamdeck-mode) | Quick Controls button that turns the PC into a Steam Deck streaming host: Sunshine + MoonDeck Buddy, a dedicated headless output, dark desk with a password overlay. *Not yet fully verified on 1.3.* |
| [mpris-player-fixes](packages/mpris-player-fixes) | Browser-player fixes: no seek bar pinned at the end, a Zen icon, YouTube thumbnails as cover art, plus a companion userscript |
| [bar-glance](packages/bar-glance) | Frame-attached popouts for clock, controls, battery and layout, a Bluetooth widget with flyout and battery readout, and night weather glyphs |
| [multi-monitor-fixes](packages/multi-monitor-fixes) | Monitor hotplug without a reload, wallpaper-manager handoff, notch and fullscreen-detection fixes for multi-screen setups |
| [audio-routing](packages/audio-routing) | Notch tab for per-app outputs, volumes and microphones, with EasyEffects as a first-class route |
| [vram-diet](packages/vram-diet) | Cuts the shell's GPU memory footprint (827 to 439 MiB on a two-monitor 3440x1440 setup) with no visual change |
| [mod-updater](packages/mod-updater) | Update checking for Settings > Mods: a Check for updates button, per-mod Update buttons, optional automatic checks and installs |
| [settings-float](packages/settings-float) | Opens the Settings window floating and centred, sized to the screen, through Ambxst's own compositor abstraction (Hyprland, Niri, Mango) |

More are on the way as they are ported from a long-running personal fork.

## License

MIT.
