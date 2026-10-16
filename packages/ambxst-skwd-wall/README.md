# Ambxst Skwd-wall

Hands every wallpaper to [skwd-wall](https://github.com/liixini/skwd-wall)'s renderer,
images, videos and GIFs alike, and brings its transitions into Ambxst's wallpaper
settings. Ambxst keeps your library, its picker, per-screen wallpapers and matugen
colours; skwd-wall draws them.

It replaces the **Wallpaper Transitions** mod (by POSiTiiiV), whose settings panel
it builds on: disable that mod before enabling this one.

## Why

skwd decodes a video once for every screen and presents it without copying frames
around. Measured on a 4K H.264 wallpaper (24 fps) across two 3440×1440 monitors,
NVIDIA RTX 4080, against Ambxst's own player, over three alternating rounds:

| | Ambxst's player | skwd-wall |
|---|---|---|
| Video decoder load | ~21.6 % | ~9.5 % |
| CPU (shell + renderer) | ~23–25 % of a core | ~3–9 % of a core |
| VRAM | — | ~450 MB less |
| RAM | — | ~550–880 MB less |
| GPU load | ~49–54 % | ~42–50 % |

Your numbers will differ with your GPU, monitors and videos.

## Requirements

skwd-wall's renderer and its control daemon. On Arch:

```bash
yay -S skwd-deck-bin skwd-paper-bin
```

You do not need skwd-wall's own picker, and you do not need to enable its service:
the mod starts `skwd-walld` itself. Other distributions: see
[skwd-wall's install notes](https://github.com/liixini/skwd-wall#installation).

## Install

```bash
ambxst mods disable positive.wallpaper-transitions   # if you have it
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/ambxst-skwd-wall
ambxst mods enable drpezzer.ambxst-skwd-wall
ambxst reload
```

Or paste the link into **Settings → Mods**.

## What you get

Open the notch on the **Wallpapers** tab:

- **Shuffle** picks a random wallpaper (also `ambxst run wallpaper-random`, for a keybind).
- **The gear** opens the wallpaper settings inside the notch:
  - **Transition Style**: a looping carousel of skwd-wall's 39 transitions plus
    Random and Instant. The chosen one is the card in the middle, playing a line
    drawing of the effect; its neighbours fold into named bars on either side. Scroll,
    click a bar or use the arrow keys to bring another to the middle. Tabs above it
    narrow the loop to one family (Fade, Wipe, Warp, Break up, Sand).
  - **Animation Duration**: how long skwd-wall takes to play the transition.
  - **Automation & Rotation**: automatic rotation on a preset or custom timer, *Match
    Time of Day* (wallpapers sorted by brightness and warmth into morning, afternoon,
    sunset and night), and which folders and kinds the shuffle draws from.
  - **Live Wallpaper Playback & Power Saving**: pause videos while a window is
    fullscreen (or maximized), on that monitor only or on all of them. skwd-wall does
    the pausing itself.
  - **Material You colour schemes** and **colour presets**.

Everything in the panel follows your Ambxst theme, including the colours and
styles you chose for each surface type.

Your settings from Wallpaper Transitions carry over; its transition styles are
mapped to the nearest skwd-wall one (the slides become Push Up, Circle Expand
becomes Iris Open, Circle Shrink becomes Circle Crop, Zoom & Fade becomes Zoom Blur
Pull, and so on). Easing curves are gone: skwd-wall's transitions have none.

## How it behaves

- skwd-wall runs while the mod is enabled and draws every screen's wallpaper.
  Ambxst's own video player sits idle.
- If skwd-wall is not installed, or its daemon cannot be reached, Ambxst draws and
  plays everything itself, as before.
- skwd-wall draws on the layer just above Ambxst's wallpaper, so anything Ambxst
  draws *into* its wallpaper (such as the blurred wallpaper behind the overview) is
  hidden while skwd-wall is running.
- Leave skwd-wall's own colour theming off (it is off unless you set it up in its
  picker). Ambxst keeps generating your colours.

## Options

`~/.config/ambxst/skwd-wall.json` (created on first run, re-read live):

```json
{
    "enabled": true
}
```

`enabled: false` hands everything back to Ambxst and stops skwd-wall. The transition
and pause settings are written into skwd-wall's own config
(`~/.config/skwd-wall-v2/config.json`, the `transition` and `playback` keys).

## Removing it

Disable the mod and `ambxst reload`, then `systemctl --user stop skwd-walld` (the mod
stops it itself while it runs, but a disabled mod no longer runs).

## Credits

- Rendering: [skwd-wall](https://github.com/liixini/skwd-wall) by liixini.
- The wallpaper settings panel, shuffle, rotation and colour-preset fixes come from
  [Wallpaper Transitions](https://github.com/POSiTiiiV/ambxst-mods/tree/main/packages/wallpaper-transitions)
  by POSiTiiiV, MIT licensed (see `LICENSE-wallpaper-transitions`).

## Changelog

- 1.0.0: first release, tested on Ambxst 1.3.12 with skwd-wall 1.0.0-beta.26.
