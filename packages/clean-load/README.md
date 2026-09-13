# Ambxst Clean Load

Gives Ambxst a fluid way in and out.

Stock Ambxst assembles itself in pieces: the wallpaper pops in whenever its
image has decoded, the frame and bar appear a beat later, and the closed AI
sidebar sweeps across the screen once on the way. `ambxst reload` is worse:
Quickshell is killed outright, so wallpaper, frame and bar vanish in one frame
and the compositor backdrop shows until the new shell has loaded a second or
two later.

With this mod a reload is one staged movement:

1. **Out** (about 1.4 s). The bar, notch and dock ease out past the screen
   edges first; the frame follows them out a beat later and the windows expand
   into the space; the wallpaper is the slowest, still fading to the theme
   background colour after the rest has gone. Nothing snaps.
2. The shell restarts on a quiet, plain background.
3. **In** (about 0.95 s). The wallpaper starts fading up first; the frame
   closes in from the edges with its rounding while the windows shrink back
   to make room; the bar, notch and dock arrive last, decelerating into place.

A cold boot gets step 3 on its own today; dedicated first-boot polish is planned.

| leave (L = 900 ms)          | enter (E = 650 ms)          |
|-----------------------------|-----------------------------|
| chrome  0 .. 0.85 L, in-out-cubic | curtain 0 .. 1.4 E, out-cubic |
| frame   0.2 L .. 1.2 L, in-out-cubic | frame 0.2 E .. 1.2 E, out-cubic |
| curtain 0.1 L .. 1.5 L, in-out-sine | chrome 0.45 E .. 1.45 E, out-cubic |

## How it works

**Entering.** A singleton (`ShellTransitions`) drives three staged channels
(`progress` for the frame, `chromeProgress` for bar, notch and dock, `curtain`
for the wallpaper sheet) once the bar and theme config are loaded, the
compositor's monitor and window state has arrived, and the first wallpaper
image has decoded. The frame's thickness and inner radius scale by the first,
the bar, notch and dock offsets by the second, a sheet in the theme background
colour sits over the wallpaper at the third's opacity, and the reservation
windows only reserve space while the frame is in place, which is what makes
the compositor's windows follow. Waiting for the compositor state matters:
until it arrives the notch and dock believe the workspace is empty and reveal
themselves, only to hide again a moment later.

**Leaving.** Quickshell exits about ten milliseconds after the `SIGTERM`
that `ambxst reload` sends, without running any QML teardown, so the shell
cannot animate out once the reload has been issued. It has to leave first.
Three entry points do that:

- `ambxst run reload` (also usable as a keybind command) leaves, then issues
  `ambxst reload` itself when the animation is done.
- `qs ipc --pid $(cat $XDG_RUNTIME_DIR/ambxst-qs.pid) call cleanload reload`
  does the same over IPC; `... call cleanload leave` only plays the
  animation and returns how many milliseconds it takes.
- **The `ambxst` wrapper in `extras/`** makes a plain `ambxst reload` typed
  anywhere (terminal, the stock keybind, the launcher action, the Mods panel's
  "Restart now") do the same. Install it earlier in `PATH` than the real
  binary:

      cp extras/ambxst-wrapper ~/.local/bin/ambxst && chmod +x ~/.local/bin/ambxst

  Every other subcommand passes straight through. If the shell is not running
  or does not answer within a second, the real reload runs at once.

  Shells that were already open when you installed the wrapper still have the
  real binary cached: run `hash -r` in them (or open a new terminal), or a
  plain `ambxst reload` there is a cold kill and the windows snap instead of
  following the frame.

**The veil.** For a cold kill without the wrapper (a plain `ambxst reload`,
the watchdog, a crash), a tiny detached Quickshell helper (`veil/Veil.qml`)
that the shell keeps connected over a local socket maps the last wallpaper and
frame the instant the shell's socket closes, plays the leave animation itself
(frame collapses into the edge, wallpaper fades to the background colour), and
holds that until the new shell reports its wallpaper is up. It is idle and
windowless while the shell runs, imports nothing from the shell, and exits
after each reload; the new shell spawns a fresh one.

**Windows move with the frame.** The compositor moves the windows into and
out of the frame's space with its own resize animation, which on Hyprland is
`windowsMove` (250 ms by default), so they used to snap ahead of the frame.
For the duration of a transition the mod retunes `windowsMove` to the frame
channel's duration and easing over `hyprctl eval`, then restores what was
there (the effective value, walking up to `windows` or the global default if
`windowsMove` itself was not set). The original is also written to
`$XDG_STATE_HOME/ambxst/clean-load-windowsmove.json` for the duration,
so a shell killed mid-transition still gets it restored by the next one.
Hyprland only; other compositors are left alone.

**Corner windows.** Stock Ambxst creates its screen-corner windows before the
theme file has loaded, so they flash as bare boxes at every screen corner for
a moment; they now wait for the theme and only exist while the frame is in
place.

**Volume and brightness pop-ups.** The on-screen display shows whenever the
audio or brightness service reports a change, and both also report while
reading their initial state after a start: the PipeWire sink and source sync
within the first second or so, and every monitor reports the moment its first
brightness read lands, which over DDC can be ten seconds after the shell came
up. So the pop-up plays over the entry, or long after it, on every reload. By
default the mod swallows exactly those reports: volume and microphone while
the start window is open (the entry plus 1.5 s), brightness when the report is
the one that turned its monitor ready (which also covers the re-read after a
wake or a monitor hotplug). A real key press or slider change still shows it.
The display can also be turned off altogether.

**Sidebar fix.** The AI assistant sidebar's slide was a `Behavior` on its
`x`, and `x` depends on the panel width, so the first layout (panel width 0 to
screen width) and the config-driven width change both played the slide with
the sidebar visible. It now animates only when it is actually opened or closed.

## Settings

Under Settings > Mods > Ambxst Clean Load:

- **Animate the shell in on start** (on). Off gives the stock pop-in.
- **Enter duration** (650 ms). The base E of the table above.
- **Leave duration** (900 ms). The base L.
- **Cover a cold kill with the veil helper** (on). Starts or stops the helper
  on the next reload.
- **On-screen display** (Quiet at start). *Quiet at start* hides the volume,
  microphone and brightness pop-ups for the initial reads after a start and
  shows them for real changes; *As stock* always shows them; *Off* never does.

## Notes

- The compositor's own backdrop shows for the second or two the restart
  takes, so set it to your theme background. On Hyprland:

      misc { disable_hyprland_logo = true; force_default_wallpaper = 0; background_color = 0x000000 }

  (Ambxst's OLED mode uses pure black; otherwise use your theme's background.)
- The helper costs 50-100 MB of private memory while idle and nothing on the
  GPU. With `ambxst quit` there is no new shell; it drops the wallpaper after
  12 s and exits.
- Video and GIF wallpapers are held as the still frame Ambxst already caches
  for the lockscreen.
- On Hyprland the helper's surfaces use the `ambxst:` namespace prefix so the
  layer rules Ambxst generates (no animation, blur) apply to them too.
- The mod does not wait for `Config.initialLoadComplete` on purpose: that flag
  also waits for optional config files (`ai.json`, `general.json`,
  `prefix.json`) and never comes true on an install where they are absent.
- After a transition Hyprland reports `windowsMove` as overridden with the
  values it had effectively before; that is the same behaviour unless you
  later change `windows` and expect `windowsMove` to follow. Ambxst reloads
  the Hyprland config at every shell start anyway, which resets it.
- `setsid` (util-linux) is used to detach the helper from Quickshell's process
  group, which the Ambxst daemon kills as a whole on shutdown.
- For diagnostics: `qs ipc --pid $(cat $XDG_RUNTIME_DIR/ambxst-qs.pid) call cleanload state`
  (`osdSwallowed` counts the initial-state pop-ups that were held back, per
  screen, since the shell started).

## Changelog

- 1.1.0: the volume, microphone and brightness pop-ups no longer appear on
  their own after a start (new **On-screen display** setting, which can also
  turn the display off).
- 1.0.0: initial release, verified on Ambxst 1.3.3 (base af9f8ad4).
