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

## Compatibility

Pure insertions and self-contained rewrites; the touched files are
`shell.qml` (pragma block), `ScreenFrameContent.qml` (visuals section only),
`ScreenCorners.qml`, `TintedWallpaper.qml`, `Overview.qml`,
`ScrollingWorkspace.qml`, `FullPlayer.qml`, `ScreenshotOverlay.qml` and
`Wallpaper.qml` (one line). Composes cleanly next to the other drpezzer mods.

## Changelog

- 1.0.1: 1024x1024 texture atlas (was sized to the screen).
- 1.0.0: initial release. 827 -> 439 MiB on the setup above; frame edges pixel-identical to stock (zero differing pixels on all four edge strips), corner windows verified mapping at 28x28 with the frame on.
