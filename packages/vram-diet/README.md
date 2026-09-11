# VRAM diet

Cuts the shell's GPU memory footprint without removing or changing any feature.
Everything looks and behaves the same; the shell just keeps fewer and smaller
textures and surfaces alive.

## What it changes

| Change | Where | Why it saves memory |
|---|---|---|
| `QSG_NO_DEPTH_BUFFER=1` via a root-file pragma | `shell.qml` | Qt Quick attaches a depth/stencil buffer to every window swapchain and every offscreen layer even though a 2D scene never reads it. Dropping it saves ~16 MiB per screen-sized surface and ~8 MiB per screen-sized layer on a 3440x1440 monitor, plus a fixed slice on each of the hundreds of small layers the shell keeps (icon tints, pill shadows). Rendering output is identical. |
| `QSG_ATLAS_WIDTH/HEIGHT=1024` via pragmas | `shell.qml` | Qt sizes its small-texture atlas to the next power of two above the screen: 4096x2048 (32 MiB) per window on a 3440x1440 monitor, 64 MiB on 4K. The shell's icons fit in a 1024x1024 (4 MiB) atlas; if one fills up Qt opens another. Identical output. |
| Frame drawn as four strips + four corner fillers | `modules/frame/ScreenFrameContent.qml` | The stock frame renders a screen-sized fill into an offscreen texture and punches the inner rounded rectangle out with a second screen-sized mask texture: two full-screen FBOs per monitor, allocated even with the frame disabled. Strips and corner canvases cost nothing. The masked path is kept and used automatically when the background style is a multi-stop gradient or halftone pattern, where a continuous pattern around the frame is needed. Nothing is allocated while the frame is off. |
| Screen corners as four corner-sized windows | `modules/corners/ScreenCorners.qml` | The stock corners are one full-screen transparent overlay surface per monitor that paints four 20 px corners. Four 20x20 windows keep the same namespace, layer, click-through mask and fullscreen hiding. |
| Wallpaper `mipmap: false` | `modules/widgets/dashboard/wallpapers/Wallpaper.qml` | The wallpaper is decoded at screen size and only ever magnified, so mip levels are never sampled. Saves a third of the wallpaper texture per monitor. |
| `maxSourceDim` on `TintedWallpaper` | `modules/components/TintedWallpaper.qml`, overview tiles | Overview tiles decoded the wallpaper at its native (often 4K) resolution to fill a few hundred pixels. They now decode at twice the tile size. Lockscreen use is unchanged (natural size). |
| Decode caps on two more images | `FullPlayer.qml` (1280 px), `ScreenshotOverlay.qml` (512 px) | The player background fell back to the native wallpaper; the 250 px screenshot preview uploaded the whole screenshot. |

## Measured

3440x1440, two monitors, NVIDIA (`nvidia-smi` per-process figure for `qs`), fresh
shell right after login, dock + frame on, corners off:

| | qs VRAM |
|---|---|
| stock 1.3.1 | 827 MiB |
| with VRAM diet | 439 MiB |

Unit costs measured with a bare Quickshell probe on the same setup: a
screen-sized layer surface is ~44 MiB (31 without the depth buffer), a
screen-sized offscreen layer ~22 MiB, the MultiEffect shadow chain on a
screen-sized layer ~26 MiB, and 200 tiny (32x32) layers ~38 MiB (21 without the
depth buffer).

## What to expect on other setups

Savings scale with pixel count, so bigger screens gain more. Rough per-monitor
figures from the unit costs above (frame on; add the corners row if you use
corners):

| Monitor | depth buffers | frame textures | atlas | wallpaper mips | total | corners (if on) |
|---|---|---|---|---|---|---|
| 1920x1080 | ~20 MiB | ~16 MiB | 16 -> 4 MiB | ~3 MiB | **~50 MiB** | +13-18 MiB |
| 2560x1440 | ~35 MiB | ~28 MiB | 32 -> 4 MiB | ~5 MiB | **~95 MiB** | +25-35 MiB |
| 3440x1440 | ~50 MiB | ~38 MiB | 32 -> 4 MiB | ~7 MiB | **~120 MiB** | +30-45 MiB |
| 3840x2160 | ~80 MiB | ~63 MiB | 64 -> 4 MiB | ~11 MiB | **~215 MiB** | +50-75 MiB |

Plus a share of the small-layer overhead that does not depend on resolution.
On the two-ultrawide test rig the measured total was 442 MiB.

- **Laptops / integrated GPUs**: VRAM is carved out of system RAM there, so
  every MiB above is also a MiB of RAM back. Nothing in the mod is
  NVIDIA-specific; the pragmas are Qt scene-graph settings that apply to the
  OpenGL and Vulkan backends alike, on Mesa or proprietary drivers.
- **HiDPI / fractional scaling**: the decode caps are in logical pixels and are
  multiplied by the screen's device pixel ratio, so a scaled laptop panel still
  gets oversampled textures. Frame strips and corner windows use the same
  logical geometry as stock and render at native DPR. Only tested at scale 1
  (two 3440x1440 monitors); the HiDPI paths are correct by construction but
  screenshots from a scaled panel are welcome.
- **Compositors**: the four corner windows are plain layer-shell surfaces with
  the same `ambxst:screenCorners` namespace as stock, so existing layer rules
  on Hyprland, niri and mango match them unchanged.
- **Quickshell**: the `//@ pragma Env` lines need Quickshell >= 0.1.0, which
  is older than the `DataDir` pragma Ambxst 1.3 already relies on. `Env`
  overrides a variable of the same name set in your session; if you set
  `QSG_NO_DEPTH_BUFFER` or `QSG_ATLAS_*` yourself, this mod wins.
- **Gradient / halftone frame styles** automatically keep the stock masked
  frame renderer, so themes with a pattern running around the frame are
  unchanged (and keep the stock cost).

## Compatibility

Pure insertions and self-contained rewrites; the touched files are
`shell.qml` (pragma block), `ScreenFrameContent.qml` (visuals section only),
`ScreenCorners.qml`, `TintedWallpaper.qml`, `Overview.qml`,
`ScrollingWorkspace.qml`, `FullPlayer.qml`, `ScreenshotOverlay.qml` and
`Wallpaper.qml` (one line). Composes cleanly next to the other drpezzer mods.

## Changelog

- 1.0.3: verified on Ambxst 1.3.3 (base af9f8ad4); patch applies verbatim, no source changes.
- 1.0.2: decode caps scale with the screen's device pixel ratio (HiDPI laptops); portability notes.
- 1.0.1: 1024x1024 texture atlas (was sized to the screen).
- 1.0.0: initial release. 827 -> 439 MiB on the setup above; frame edges pixel-identical to stock (zero differing pixels on all four edge strips), corner windows verified mapping at 28x28 with the frame on.
