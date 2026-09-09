# MPRIS player fixes

Fixes for browser players in Ambxst's compact, full and lock media players.

- **Seek bar no longer pins at the end.** Firefox and Zen only publish a track
  length when the page keeps `navigator.mediaSession` position state
  populated. When they don't, Quickshell reports length equal to position and
  the bar reads as finished the instant playback starts. The players now use
  `lengthSupported`, keep the last good length across metadata flaps, and show
  `--:--` when there is genuinely no duration.
- **Zen gets its own icon.** Zen registers on D-Bus as
  `org.mpris.MediaPlayer2.firefox.instance*`, so stock Ambxst showed the
  Firefox glyph. Zen is matched on its desktop entry and identity first, and a
  white ring logo ships with the mod.
- **YouTube thumbnails as cover art.** Firefox and Zen clear `mpris:artUrl` on
  every metadata change and often never republish it. When it is empty the
  players derive the thumbnail from the watch URL in `xesam:url`, using the
  `mqdefault` variant because it is the only 16:9 one YouTube generates for
  every video.

## Install

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/mpris-player-fixes
```

Paste that into **Settings → Mods**, or:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/mpris-player-fixes
ambxst mods enable drpezzer.mpris-player-fixes
ambxst reload
```

## The browser half: a userscript for YouTube

YouTube's single-page navigation stops re-pushing position state after the
first video, so Firefox and Zen drop `mpris:length` and `Position` and the
playhead sticks at 0 until you pause and play. That is a browser-side gap and
no shell change can close it, so this package ships a tiny userscript that
re-pushes `setPositionState()` on every `timeupdate` and page navigation.

1. Install [Violentmonkey](https://violentmonkey.github.io/) in Firefox or Zen.
2. Open this link; Violentmonkey will offer to install it:

   https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/packages/mpris-player-fixes/extras/youtube-mpris-position.user.js

It only matches `youtube.com` and `music.youtube.com`. Other sites with the
same problem still show a stuck playhead until their page pushes position
state itself.

## What it changes

- New: `modules/theme/icons/zen-browser.svg`.
- `modules/services/MprisController.qml` — `artUrlFor()` and the YouTube id parser.
- `modules/theme/Icons.qml` — `Icons.zen`.
- `modules/components/PositionSlider.qml`, `FullPlayer.qml`, `LockPlayer.qml`,
  `CompactPlayer.qml` — the length guard, the Zen match, and the art fallback.

Works with Ambxst `>=1.3.0`. No new config keys.

## Changelog

- **1.1.0** — ships the Zen icon and the YouTube userscript.
- **1.0.0** — first packaged release.
