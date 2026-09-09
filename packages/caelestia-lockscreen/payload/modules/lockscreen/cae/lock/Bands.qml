pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Services
import qs.modules.theme as AmbxstTheme

// The three diagonal bars in the bottom-right corner, turned into live vitals
// gauges in the same visual language as Ambxst's volume/mic/brightness sliders:
// the used part of each bar is an animated sine that tightens as the value
// climbs, the rest is the flat track. Wave maths and the 8x/1.5x scaling are
// taken from modules/components/WavyLine.qml and modules/bar/VolumeSlider.qml.
//
// Readings come from Caelestia's compiled services rather than Ambxst's
// SystemResources: that one only runs while the dashboard's metrics tab is open
// (`running: GlobalStates.dashboardOpen && dashboardCurrentTab === 2`), so on a
// lockscreen it reports zeros and every bar sits flat. The ServiceRefs below are
// what start the polling.
//
// The Ambxst import is qualified: both this port and the shell export a
// `Colors`, and an unqualified import silently binds the wrong one.
//
// Geometry keeps the hyprlock config's angle, spacing and relative widths, but
// measured against a 16:9 box of the screen's height rather than its actual
// width - on this 21:9 screen the raw fractions push the third bar off the
// display entirely (hyprlock itself only draws two here).
//
// Bars are thinner than the config's slabs: a sine drawn with a 230px stroke at
// eight cycles overlaps itself into a blob, so the wave needs a line thin
// relative to its wavelength to read at all. The 16 : 12.8 : 10.67 ratio between
// them is kept.
Item {
    id: root

    readonly property real refWidth: height * 16 / 9
    readonly property real angleDeg: -45
    readonly property real span: 1.4

    // Nearest the corner first: RAM, then GPU, then CPU on the outermost bar.
    readonly property var bars: [
        {
            key: "ram",
            offset: 0.766,
            thickness: 0.0171
        },
        {
            key: "gpu",
            offset: 0.655,
            thickness: 0.0205
        },
        {
            key: "cpu",
            offset: 0.521,
            thickness: 0.0256
        }
    ]

    // Already 0..1 from these services, unlike SystemResources' 0..100.
    function usage(key: string): real {
        if (key === "cpu")
            return Cpu.percentage;
        if (key === "ram")
            return Memory.percentage;
        return Gpu.percentage;
    }

    // The colours the metrics panel uses, so a bar is identifiable without a
    // label: CPU red, RAM cyan, GPU by vendor.
    function tint(key: string): color {
        if (key === "cpu")
            return AmbxstTheme.Colors.red;
        if (key === "ram")
            return AmbxstTheme.Colors.cyan;

        // Ambxst tints the GPU bar by vendor. This service only separates
        // Nvidia from everything else, so an AMD or Intel card lands on the
        // panel's default magenta rather than its red or blue.
        return Gpu.type === Gpu.Nvidia ? AmbxstTheme.Colors.green : AmbxstTheme.Colors.magenta;
    }

    // Nothing polls these until something references them.
    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Gpu
    }

    Repeater {
        model: root.bars

        Canvas {
            id: bar

            required property var modelData

            // Not readonly: the Behavior below animates it, which a readonly
            // property refuses.
            property real value: root.usage(modelData.key)
            readonly property color tint: root.tint(modelData.key)
            readonly property real thickness: root.height * modelData.thickness

            anchors.fill: parent
            renderStrategy: Canvas.Cooperative

            // The bar's translucency lives here rather than in the individual
            // fills. Overlapping translucent draws blend with each other - the
            // dot over the wave came out with a darker rim around it, and the
            // wave darkened wherever it crossed itself. Drawing every stroke
            // opaque and fading the whole canvas once composites them as a
            // single object instead.
            opacity: 0.75

            // Same mapping as the volume slider: both the tightness and the
            // depth of the wave ride the value, so a busy core reads as a
            // compressed ripple and an idle one as a nearly flat line.
            readonly property real frequency: 8 * value
            readonly property real amplitude: thickness * 1.5 * value

            Behavior on value {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (width <= 0 || height <= 0)
                    return;

                const a = root.angleDeg * Math.PI / 180;
                const ux = Math.cos(a);
                const uy = Math.sin(a);
                // Normal, for the wave's excursion off the bar's axis.
                const nx = -uy;
                const ny = ux;

                const cx = width / 2 + modelData.offset * root.refWidth;
                const cy = height / 2;
                const half = root.span * root.refWidth / 2;

                // Clip the bar's centreline to the screen, so the gauge runs
                // across the part that is actually visible rather than the long
                // stretch of it that sits off the display.
                let t0 = -half;
                let t1 = half;
                const clip = (p, q) => {
                    if (Math.abs(p) < 1e-9)
                        return q >= 0;
                    const r = q / p;
                    if (p < 0) {
                        if (r > t1)
                            return false;
                        if (r > t0)
                            t0 = r;
                    } else {
                        if (r < t0)
                            return false;
                        if (r < t1)
                            t1 = r;
                    }
                    return true;
                };

                if (!clip(-ux, cx) || !clip(ux, width - cx) || !clip(-uy, cy) || !clip(uy, height - cy))
                    return;
                if (t1 - t0 < 1)
                    return;

                // Run both ends past the screen edge so their round caps fall
                // outside it. Clipped exactly to the edge, the line stops with a
                // visible rounded tip instead of bleeding off the display.
                const bleed = bar.thickness * 2;
                t0 = Math.max(-half, t0 - bleed);
                t1 = Math.min(half, t1 + bleed);

                const len = t1 - t0;
                const sx = cx + ux * t0;
                const sy = cy + uy * t0;
                const split = len * bar.value;
                const phase = Date.now() / 400;

                ctx.lineCap = "round";
                ctx.lineWidth = bar.thickness;

                // Remaining: the flat track. Alphas below are relative to the
                // canvas opacity above, so 0.24 lands at the 0.18 it had before.
                ctx.strokeStyle = Qt.alpha(bar.tint, 0.24);
                ctx.beginPath();
                ctx.moveTo(sx + ux * split, sy + uy * split);
                ctx.lineTo(sx + ux * len, sy + uy * len);
                ctx.stroke();

                // Used: the wave. It is eased back onto the axis over its last
                // stretch so it arrives where the dot is rather than at whatever
                // height the sine happened to reach - otherwise a crest at the
                // split pokes out past the dot on one side.
                const taper = Math.min(split, bar.thickness * 3);

                ctx.strokeStyle = bar.tint;
                ctx.beginPath();
                for (let s = 0; s <= split; s += 2) {
                    const settle = taper > 0 ? Math.min(1, (split - s) / taper) : 1;
                    const off = settle * bar.amplitude * Math.sin(bar.frequency * 2 * Math.PI * s / len + phase);
                    const px = sx + ux * s + nx * off;
                    const py = sy + uy * s + ny * off;
                    if (s === 0)
                        ctx.moveTo(px, py);
                    else
                        ctx.lineTo(px, py);
                }
                ctx.stroke();

                // The wave ends wherever the sine happens to be, while the track
                // resumes on the axis, so the two never quite line up. This sits
                // on the axis at the split and covers the join, the way the
                // slider's drag handle does.
                //
                // Opaque, so it simply covers the join - no clearing pass and
                // no rim. Sized to swallow the wave's rounded end cap.
                ctx.fillStyle = bar.tint;
                ctx.beginPath();
                ctx.arc(sx + ux * split, sy + uy * split, bar.thickness * 0.95, 0, 2 * Math.PI);
                ctx.fill();
            }

            FrameAnimation {
                running: bar.visible && bar.opacity > 0
                onTriggered: bar.requestPaint()
            }
        }
    }
}
