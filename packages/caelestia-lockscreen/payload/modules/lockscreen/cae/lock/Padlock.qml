pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Config
import qs.modules.lockscreen.cae.services

// A literal port of Hypr-Prelock's main.c - the animation this lockscreen is
// modelled on. Every constant below is that file's: rays starting at
// ease*120+30 and running to the screen edge, a 12px ring closing clockwise from
// twelve o'clock at radius 120, a 3px ring closing anticlockwise at 145, and a
// padlock that turns upright while its shackle drops into the body.
//
// `progress` must be advanced LINEARLY. The sin(p * PI/2) ease is applied here,
// exactly as the C code does internally; easing the driver as well flattens the
// whole sweep.
//
// Raylib and Qt agree on arc convention - degrees, 0 at three o'clock, positive
// sweeping clockwise in y-down coordinates - so the angles carry over unchanged
// (270 is written as -90).
Item {
    id: root

    required property real progress
    required property real contentScale

    // Pixel unit: the C code draws in raw pixels on a 1080p-ish screen, so at
    // 1440p this is 1:1 and only the 4K screen scales up.
    readonly property real u: contentScale

    readonly property real ease: Math.sin(progress * Math.PI / 2)
    readonly property color tint: Colours.palette.m3primary
    readonly property real ringAlpha: 1 - progress * 0.2

    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // Two rays out to the screen edges, fading as they extend. Alpha tracks
    // progress, not the eased value.
    Repeater {
        model: [-1, 1]

        Rectangle {
            required property int modelData

            readonly property real start: (root.ease * 120 + 30) * root.u
            readonly property real len: root.ease * root.width / 2

            x: modelData < 0 ? root.cx - start - len : root.cx + start
            y: root.cy - height / 2
            width: Math.max(0, len)
            height: Math.max(1, 2 * root.u)

            color: root.tint
            opacity: Math.max(0, 1 - root.progress)
        }
    }

    // Thick ring, closing clockwise. A stroke straddles its radius, so the
    // radius is pulled in by half the width to put the outer edge on 120.
    Shape {
        anchors.fill: parent

        preferredRendererType: Shape.CurveRenderer
        opacity: root.ringAlpha

        ShapePath {
            strokeColor: root.tint
            strokeWidth: 12 * root.u
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: Math.max(0.01, (root.ease * 120 - 6) * root.u)
                radiusY: radiusX
                startAngle: -90
                sweepAngle: root.ease * 360
            }
        }
    }

    // Thin ring, closing anticlockwise.
    Shape {
        anchors.fill: parent

        preferredRendererType: Shape.CurveRenderer
        opacity: root.ringAlpha * 0.6

        ShapePath {
            strokeColor: root.tint
            strokeWidth: 3 * root.u
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: Math.max(0.01, (root.ease * 145 - 1.5) * root.u)
                radiusY: radiusX
                startAngle: -90
                sweepAngle: -root.ease * 360
            }
        }
    }

    // The padlock, drawn as primitives rather than a glyph so the shackle can
    // drop into the body the way the original does.
    Item {
        id: padlock

        readonly property real shackleProgress: Math.min(1, Math.max(0, (root.progress - 0.4) / 0.35))
        readonly property real shackleEase: Math.sin(shackleProgress * Math.PI / 2)
        // Rides down into the body over the last third of the sweep.
        readonly property real baseY: (-22 - 18 * (1 - shackleEase)) * root.u

        anchors.centerIn: parent

        implicitWidth: 160 * root.u
        implicitHeight: 160 * root.u

        transformOrigin: Item.Center
        rotation: (1 - root.ease) * -180
        opacity: root.ringAlpha

        // Flattened before the opacity is applied. Without this the padlock is
        // composited part by part, so the shackle and its legs show through the
        // body wherever they overlap - the C original has the same artefact,
        // since raylib blends each primitive straight onto the framebuffer.
        layer.enabled: true

        // Shackle: the top half of a ring, inner 10 / outer 18.
        Shape {
            anchors.fill: parent

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.tint
                strokeWidth: 8 * root.u
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap

                PathAngleArc {
                    centerX: padlock.width / 2
                    centerY: padlock.height / 2 + padlock.baseY
                    radiusX: 14 * root.u
                    radiusY: radiusX
                    startAngle: 180
                    sweepAngle: 180
                }
            }
        }

        // Shackle legs. The right one is shorter, as in the original.
        Rectangle {
            x: padlock.width / 2 - 18 * root.u
            y: padlock.height / 2 + padlock.baseY
            width: 8 * root.u
            height: 34 * root.u
            color: root.tint
        }

        Rectangle {
            x: padlock.width / 2 + 10 * root.u
            y: padlock.height / 2 + padlock.baseY
            width: 8 * root.u
            height: 18 * root.u
            color: root.tint
        }

        // Body: 50x38 at (-25,-10), roundness 0.3 of the half-height.
        Rectangle {
            x: padlock.width / 2 - 25 * root.u
            y: padlock.height / 2 - 10 * root.u
            width: 50 * root.u
            height: 38 * root.u
            radius: 5.7 * root.u
            color: root.tint
        }

        // Keyhole: a circle over a tapering slot, both in raylib's DARKGRAY.
        Rectangle {
            x: padlock.width / 2 - 4 * root.u
            y: padlock.height / 2 + 1 * root.u
            width: 8 * root.u
            height: 8 * root.u
            radius: width / 2
            color: "#505050"
        }

        Shape {
            anchors.fill: parent

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                fillColor: "#505050"

                PathMove {
                    x: padlock.width / 2
                    y: padlock.height / 2 + 3 * root.u
                }
                PathLine {
                    x: padlock.width / 2 - 4 * root.u
                    y: padlock.height / 2 + 14 * root.u
                }
                PathLine {
                    x: padlock.width / 2 + 4 * root.u
                    y: padlock.height / 2 + 14 * root.u
                }
            }
        }
    }
}
