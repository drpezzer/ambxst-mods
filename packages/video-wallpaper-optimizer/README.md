# Video Wallpaper Optimizer

Plays your video wallpapers through [skwd-wall](https://github.com/liixini/skwd-wall)'s
renderer instead of Qt's media player inside the shell. Ambxst stays in charge of
everything else: the picker, your library, per-screen wallpapers and matugen colours.
Only the playback moves out.

skwd decodes a video once for every screen and presents it without copying frames
around. Measured on a 4K H.264 wallpaper (24 fps) across two 3440×1440 monitors,
NVIDIA RTX 4080, alternating the two renderers over three rounds:

| | Ambxst's player | With this mod |
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

That is all: you do not need skwd-wall's picker, and you do not need to enable its
service. The mod starts `skwd-walld` when a screen shows a video and stops it when
none does. Other distributions: see [skwd-wall's install notes](https://github.com/liixini/skwd-wall#installation).

## Install

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/video-wallpaper-optimizer
ambxst mods enable drpezzer.video-wallpaper-optimizer
ambxst reload
```

Or paste the link into **Settings → Mods**.

## How it behaves

- **Any screen shows a video:** skwd runs and shows every screen's wallpaper, so a
  screen with an image next to a screen with a video stays right. Ambxst's own player
  sits idle.
- **No screen shows a video:** skwd is stopped and Ambxst draws images, with its own
  transitions, exactly as before.
- **Pausing:** Ambxst's *pause wallpapers on fullscreen* (and game mode) still applies.
  skwd can only pause every screen at once, so it pauses when every screen showing a
  video wants it paused.
- **Fallback:** if skwd is not installed, or the daemon cannot be reached, videos play
  in Ambxst as they always did.
- **Tint stays in Ambxst:** a tinted video wallpaper keeps playing in Ambxst, because
  the tint is a shader skwd cannot apply. GIFs also stay in Ambxst.

## Options

`~/.config/ambxst/video-wallpaper-optimizer.json` (created on first run, re-read live):

```json
{
    "enabled": true,
    "stopWhenNoVideo": true
}
```

- `enabled`: `false` hands videos straight back to Ambxst's player and stops skwd.
- `stopWhenNoVideo`: `false` keeps skwd running (and showing your images) while no
  screen has a video, which avoids its ~1 s start the next time you pick one.

## Things to know

- Leave skwd-wall's own colour theming off (it is off unless you set it up in its
  picker). Ambxst keeps generating your colours from the wallpaper as usual.
- skwd draws on the layer just above Ambxst's wallpaper. Anything Ambxst draws *into*
  its wallpaper itself, such as the blurred wallpaper behind the overview, is not
  visible while skwd is showing a video.
- Removing the mod: disable it, `ambxst reload`, then
  `systemctl --user stop skwd-walld` (the mod normally does this itself, but a disabled
  mod can no longer run).

## Credits

All the rendering is [skwd-wall](https://github.com/liixini/skwd-wall) by liixini.
This mod only connects it to Ambxst.

## Changelog

- 1.0.0: first release, tested on Ambxst 1.3.12 with skwd-wall 1.0.0-beta.26.
