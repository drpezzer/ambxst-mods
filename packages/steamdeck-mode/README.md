# Steamdeck Mode

> **Status: not yet fully verified on Ambxst 1.3.** The mode ran daily on the
> 1.1.5 fork it was built for; the 1.3 package composes and the button shows,
> but a full up/down cycle with a Deck on the other end has not been re-run
> yet. Install if you're happy to test; report anything odd.

One button in the dashboard's Quick Controls turns the PC into a Steam Deck
streaming host and back.

Turning it on starts a 15-second countdown (click again to cancel). Then it
starts Sunshine and MoonDeck Buddy, creates a Hyprland headless output named
`sunshine` sized to the Deck's panel, blanks the physical monitors, and covers
them with a password overlay that shows which game the Deck is playing. Typing
your password gives you the desk back for five idle minutes before it re-locks.
Turning the mode off stops both services, removes the virtual output and wakes
the monitors. The state survives a shell reload or crash, so the desk stays
covered while you are away. Caffeine is held while the mode is on so the idle
chain cannot suspend the host mid-game, and a Topaz Starlight render queue is
paused and resumed if `~/.local/bin/topaz-starlight-ctl` exists.

> The overlay is a layer surface, not a compositor session lock. It covers the
> physical screens and grabs the keyboard, but if the shell died the desktop
> would be exposed. It is a "don't touch my desk" screen, not a security boundary.

## Requirements

The mod refuses to build unless these commands exist: `hyprctl`, `jq`,
`systemctl`, `sunshine`, `MoonDeckBuddy`.

| Piece | Arch package | Notes |
|---|---|---|
| [Sunshine](https://github.com/LizardByte/Sunshine) | `sunshine-bin` (AUR) | Mainline, **not Apollo**. Apollo's Wayland capture aborts on session start. |
| [MoonDeck Buddy](https://github.com/FrogTheFrog/moondeck-buddy) | `moondeckbuddy-appimage` (AUR) | Pairs with the MoonDeck plugin on the Deck. |
| Hyprland with the Lua config parser | | The script drives `hyprctl` through the `hl.*` API and creates a named headless output. |

Neither service should be enabled at login. The mode starts and stops them.

## One-time setup outside the shell

Copies of every file are in `extras/`.

1. **MoonDeck Buddy unit.** Buddy looks itself up by this exact unit name.
   ```bash
   cp extras/moondeckbuddy.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   ```
2. **Sunshine focus helper.** Hyprland maps new windows onto the focused
   workspace, so without this Steam opens on your desk instead of the streamed
   display.
   ```bash
   install -m 755 extras/sunshine-stream-display ~/.local/bin/
   ```
3. **`~/.config/sunshine/sunshine.conf`.** Add the lines in
   `extras/sunshine.conf.snippet`: `output_name = sunshine`, the
   `global_prep_cmd` pointing at the helper, and the NVENC quality settings.
   Do not add any audio keys. Sunshine manages its own sink.
4. **Hyprland.** Add the monitor rule and workspace rule from
   `extras/hyprland.lua.snippet`. The rule is inert while the output is absent;
   it exists so a config reload mid-session keeps the geometry. Workspace 11 must
   agree between that rule, `DECK_WORKSPACE` in `scripts/steamdeck_mode.sh`, and
   `STREAM_WS` in the focus helper.

## What it changes

- New: `modules/services/SteamDeckService.qml`, `modules/lockscreen/SteamDeckLock.qml`,
  `scripts/steamdeck_mode.sh`, `scripts/steamdeck_game.sh`, `modules/theme/icons/steamdeck.svg`.
- `QuickControls.qml` gains the button; `ControlButton.qml` learns to draw an SVG
  icon and a countdown badge; `Icons.qml` gets the icon path; `shell.qml`
  instantiates the overlay outside the session lock so the Deck's display keeps
  rendering the game.

Works with Ambxst `>=1.3.0`.
