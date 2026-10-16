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

skwd-wall's renderer and its control daemon. You don't have to install them
yourself: with the mod enabled, open the **Wallpapers** tab, press the gear (or
select the mod in **Settings → Mods**) and press **Install skwd-wall**. It downloads
skwd-deck and skwd-paper from liixini's
[GitHub releases](https://github.com/liixini/skwd-wall/releases), checks them against
the release's `SHA256SUMS`, and unpacks them into `~/.local/share/ambxst/skwd-wall`
with a user service, `ambxst-skwd-walld`. No password, nothing outside your home,
about 70 MB. The same card offers an **Update** when a newer release is out, and
lists any system package the binaries need that you don't have.

Already have skwd from your distribution or the AUR (`yay -S skwd-deck-bin
skwd-paper-bin`)? The mod uses that instead and never downloads anything.
Until skwd is installed, Ambxst draws your wallpapers itself, as before.

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
    the pausing itself. *That monitor only* gives each monitor its own video player,
    so a video shown on two screens is decoded twice; *All monitors* shares one.
  - **Material You colour schemes** and **colour presets**.

Everything in the panel follows your Ambxst theme, including the colours and
styles you chose for each surface type.

Your settings from Wallpaper Transitions carry over; its transition styles are
mapped to the nearest skwd-wall one (the slides become Push Up, Circle Expand
becomes Iris Open, Circle Shrink becomes Circle Crop, Zoom & Fade becomes Zoom Blur
Pull, and so on). Easing curves are gone: skwd-wall's transitions have none.

## How it behaves

- **Pausing**: the mod decides when a video wallpaper pauses (a fullscreen, or with
  *Maximized*, a screen-filling window on the workspace shown on that monitor) and
  tells skwd-wall; skwd-wall's own fullscreen detection is switched off because on
  Hyprland it cannot tell hidden workspaces apart. **Game mode** pauses every video
  wallpaper, whatever the pause setting.

- **Tint** (the button in the Wallpapers tab): for images, skwd-wall shows a copy
  recoloured onto your theme palette with its Palette effect (the same palette and
  maths as Ambxst's own tint), made again whenever your colours change and kept in
  `~/.cache/ambxst/skwd-tint`. skwd-wall cannot recolour videos or GIFs, so while
  Tint is on and a screen shows one, Ambxst draws and tints everything itself
  until Tint is off again.

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
    "enabled": true,
    "source": "auto"
}
```

- `enabled: false` hands everything back to Ambxst and stops skwd-wall.
- `source`: `auto` uses a system install of skwd when there is one, otherwise the
  copy the mod installed. `local` always uses the mod's own copy (and offers to
  install it). The transition
and pause settings are written into skwd-wall's own config
(`~/.config/skwd-wall-v2/config.json`, the `transition` and `playback` keys).

## Removing it

Disable the mod and `ambxst reload`, then stop skwd-wall's daemon
(`systemctl --user stop skwd-walld`, or `ambxst-skwd-walld` for the copy the mod
installed). To remove that copy: `rm -r ~/.local/share/ambxst/skwd-wall
~/.config/systemd/user/ambxst-skwd-walld.service`.

## Credits

- Rendering: [skwd-wall](https://github.com/liixini/skwd-wall) by liixini.
- The wallpaper settings panel, shuffle, rotation and colour-preset fixes come from
  [Wallpaper Transitions](https://github.com/POSiTiiiV/ambxst-mods/tree/main/packages/wallpaper-transitions)
  by POSiTiiiV, MIT licensed (see `LICENSE-wallpaper-transitions`).

## Changelog

- 1.2.2: game mode also pauses Ambxst's own video player (tinted videos) on every
  monitor, not only the focused one.
- 1.2.1: video wallpapers no longer stay paused because of a fullscreen window on a
  hidden (special) workspace: Ambxst now decides when to pause and tells skwd-wall
  per monitor, counting only the workspace actually shown. Ambxst's game mode
  pauses every video wallpaper.
- 1.2.0: Ambxst's Tint button works with skwd-wall (images recoloured onto your
  theme palette; tinted videos and GIFs fall back to Ambxst).
- 1.1.0: one-button install and update of skwd-wall from its official releases (in
  the wallpaper settings and on the mod's page), a `source` option, one shared video
  player when every screen shows the same wallpaper, a note on what per-monitor
  pausing costs.
- 1.0.0: first release, tested on Ambxst 1.3.12 with skwd-wall 1.0.0-beta.26.
