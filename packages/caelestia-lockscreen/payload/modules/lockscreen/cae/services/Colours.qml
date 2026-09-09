pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.theme

// Ambxst-backed replacement for Caelestia's Colours singleton.
//
// Keeps the upstream API (palette / tPalette / layer() / transparency / light)
// so the ~99 call sites in the lock modules need no changes, but sources every
// colour from Ambxst's Colors singleton instead of Caelestia's scheme.json.
// Ambxst names the Material "on<Role>" colours "over<Role>".
//
// Dropped from upstream: the scheme.json FileView, setMode() (shelled out to
// the caelestia CLI) and the Hyprland layer rules for caelestia-drawers.
Singleton {
    id: root

    // Kept as inert stubs: upstream code reads these, nothing here writes them.
    readonly property bool showPreview: false
    readonly property string scheme: "ambxst"
    readonly property string flavour: "default"

    readonly property bool light: getLuminance(Colors.background) > 0.5
    readonly property real wallLuminance: getLuminance(Colors.background)

    readonly property M3Palette palette: M3Palette {}
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property Transparency transparency: Transparency {}

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    // Upstream loaded a scheme from JSON here; Ambxst's Colors owns that now.
    function load(data: string, isPreview: bool): void {}

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))
    }

    component M3Palette: QtObject {
        readonly property color m3primary_paletteKeyColor: Colors.primary
        readonly property color m3secondary_paletteKeyColor: Colors.secondary
        readonly property color m3tertiary_paletteKeyColor: Colors.tertiary
        readonly property color m3neutral_paletteKeyColor: Colors.outline
        readonly property color m3neutral_variant_paletteKeyColor: Colors.outlineVariant

        readonly property color m3background: Colors.background
        readonly property color m3onBackground: Colors.overBackground
        readonly property color m3surface: Colors.surface
        readonly property color m3surfaceDim: Colors.surfaceDim
        readonly property color m3surfaceBright: Colors.surfaceBright
        readonly property color m3surfaceContainerLowest: Colors.surfaceContainerLowest
        readonly property color m3surfaceContainerLow: Colors.surfaceContainerLow
        readonly property color m3surfaceContainer: Colors.surfaceContainer
        readonly property color m3surfaceContainerHigh: Colors.surfaceContainerHigh
        readonly property color m3surfaceContainerHighest: Colors.surfaceContainerHighest
        readonly property color m3onSurface: Colors.overSurface
        readonly property color m3surfaceVariant: Colors.surfaceVariant
        readonly property color m3onSurfaceVariant: Colors.overSurfaceVariant
        readonly property color m3inverseSurface: Colors.inverseSurface
        readonly property color m3inverseOnSurface: Colors.inverseOnSurface
        readonly property color m3outline: Colors.outline
        readonly property color m3outlineVariant: Colors.outlineVariant
        readonly property color m3shadow: Colors.shadow
        readonly property color m3scrim: Colors.scrim
        readonly property color m3surfaceTint: Colors.surfaceTint

        readonly property color m3primary: Colors.primary
        readonly property color m3onPrimary: Colors.overPrimary
        readonly property color m3primaryContainer: Colors.primaryContainer
        readonly property color m3onPrimaryContainer: Colors.overPrimaryContainer
        readonly property color m3inversePrimary: Colors.inversePrimary
        readonly property color m3secondary: Colors.secondary
        readonly property color m3onSecondary: Colors.overSecondary
        readonly property color m3secondaryContainer: Colors.secondaryContainer
        readonly property color m3onSecondaryContainer: Colors.overSecondaryContainer
        readonly property color m3tertiary: Colors.tertiary
        readonly property color m3onTertiary: Colors.overTertiary
        readonly property color m3tertiaryContainer: Colors.tertiaryContainer
        readonly property color m3onTertiaryContainer: Colors.overTertiaryContainer
        readonly property color m3error: Colors.error
        readonly property color m3onError: Colors.overError
        readonly property color m3errorContainer: Colors.errorContainer
        readonly property color m3onErrorContainer: Colors.overErrorContainer

        // Ambxst has no success role; its green pair is the closest equivalent.
        readonly property color m3success: Colors.green
        readonly property color m3onSuccess: Colors.overGreen
        readonly property color m3successContainer: Colors.greenContainer
        readonly property color m3onSuccessContainer: Colors.overGreenContainer

        readonly property color m3primaryFixed: Colors.primaryFixed
        readonly property color m3primaryFixedDim: Colors.primaryFixedDim
        readonly property color m3onPrimaryFixed: Colors.overPrimaryFixed
        readonly property color m3onPrimaryFixedVariant: Colors.overPrimaryFixedVariant
        readonly property color m3secondaryFixed: Colors.secondaryFixed
        readonly property color m3secondaryFixedDim: Colors.secondaryFixedDim
        readonly property color m3onSecondaryFixed: Colors.overSecondaryFixed
        readonly property color m3onSecondaryFixedVariant: Colors.overSecondaryFixedVariant
        readonly property color m3tertiaryFixed: Colors.tertiaryFixed
        readonly property color m3tertiaryFixedDim: Colors.tertiaryFixedDim
        readonly property color m3onTertiaryFixed: Colors.overTertiaryFixed
        readonly property color m3onTertiaryFixedVariant: Colors.overTertiaryFixedVariant

        // Fetch's swatch row reads term0..term7 by index. These mirror
        // KittyGenerator.qml exactly -- that is the palette Ambxst actually
        // writes to the terminal, so the swatches show real colours rather
        // than a plausible-looking ANSI guess. Three slots differ from the
        // obvious mapping: colour 4 is primary rather than blue (deliberate,
        // see the generator), 0 is surfaceContainerLow rather than background,
        // and 7 is outline -- matugen's "white" is often a near-duplicate of
        // cyan, which put two identical swatches in the row.
        readonly property color term0: Colors.surfaceContainerLow
        readonly property color term1: Colors.red
        readonly property color term2: Colors.green
        readonly property color term3: Colors.yellow
        readonly property color term4: Colors.primary
        readonly property color term5: Colors.magenta
        readonly property color term6: Colors.cyan
        readonly property color term7: Colors.outline
        readonly property color term8: Colors.surfaceBright
        readonly property color term9: Colors.lightRed
        readonly property color term10: Colors.lightGreen
        readonly property color term11: Colors.lightYellow
        readonly property color term12: Colors.lightBlue
        readonly property color term13: Colors.lightMagenta
        readonly property color term14: Colors.lightCyan
        readonly property color term15: Colors.overSurface
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }
}
