pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.services

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running

    // Drives Padlock.qml's sweep. Animated LINEAR: the padlock applies its own
    // sin ease internally, exactly as the C original does.
    property real introProgress: 0

    // Padlock <-> composition crossfade. 0 = padlock alone, 1 = lockscreen.
    property real reveal: 0

    // Blur over the captured desktop: 0 = legible, 1 = fully obscured. Kept
    // separate from `reveal` because the unlock holds the blur through the
    // padlock's pause and only sharpens during the final fade.
    property real blurAmount: 0

    // Final fade of everything the surface draws, on unlock.
    property real outAlpha: 1

    readonly property real introEase: Math.sin(introProgress * Math.PI / 2)

    // Everything is laid out against a 1440p reference, matching Content.qml.
    readonly property real contentScale: (root.screen?.height ?? 1440) / 1440

    // The composition and password field only appear on one screen; every other
    // screen just shows the blurred desktop. Empty shows it everywhere, the safe
    // fallback.
    //
    // Chosen by shell.qml, not here: it prefers config/lockscreen.json's
    // `screen` and only falls back to the monitor the pointer was on, which it
    // has to freeze at lock time because Hyprland's IPC connects lazily and
    // reports nothing on first access - and a surface created at lock time is
    // exactly that first access.
    required property string cardScreenName

    readonly property bool cardScreen: cardScreenName === "" || root.screen?.name === cardScreenName

    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name

    color: "transparent"

    Connections {
        function onUnlock(): void {
            unlockAnim.start();
        }

        target: root.lock
    }

    // Entry, timed off the reference recording: the padlock sweeps in over
    // 1.2s, everything holds for 0.7s, then the composition crossfades in.
    //
    // The sweep is ticked forward per frame rather than run as a NumberAnimation
    // because Qt's animations are driven by the wall clock: the surface spends
    // its first ~0.9s loading the desktop grab synchronously and compiling the
    // blur shader, and a time-based animation spends that budget unseen, so the
    // padlock pops in already three-quarters drawn. A timer cannot run while the
    // render thread is blocked and Qt coalesces the missed ticks, so this
    // advances only on frames that are actually shown - the same way the C
    // original accumulates GetFrameTime().
    Timer {
        id: introTicker

        interval: 16
        repeat: true
        running: root.introProgress < 1

        onTriggered: {
            root.introProgress = Math.min(1, root.introProgress + interval / 1200);
            if (root.introProgress >= 1)
                revealAnim.start();
        }
    }

    SequentialAnimation {
        id: revealAnim

        PauseAnimation {
            duration: 700
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "reveal"
                to: 1
                duration: 350
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "blurAmount"
                to: 1
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
    }

    // Exit, the same beats in reverse: the composition crossfades back to the
    // padlock, which then holds before the whole surface fades out and the
    // desktop sharpens under it.
    SequentialAnimation {
        id: unlockAnim

        // The composition and the blur leave together: in the original both
        // belong to hyprlock, which exits as one, leaving the padlock sitting on
        // a sharp desktop under nothing but the scrim. Holding the blur through
        // the pause instead turns that beat into a dark, muddy screen.
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "reveal"
                to: 0
                duration: 300
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "blurAmount"
                to: 0
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        // The padlock is alone on screen for a beat. In the original this is the
        // gap between hyprlock exiting and the script touching the file that
        // releases the animation; here it is just held.
        PauseAnimation {
            duration: 500
        }

        // The scrim and padlock fade out together, 0.3s, exactly as the C code's
        // globalAlpha ramp does.
        NumberAnimation {
            target: root
            property: "outAlpha"
            to: 0
            duration: 300
            easing.type: Easing.Linear
        }

        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    // The lockscreen background: the desktop as captured by shell.qml just
    // before the lock engaged.
    //
    // A live ScreencopyView cannot do this -- it has no content for its first
    // frames and can never capture once locked, so both ends of the animation
    // uncovered black instead of the desktop.
    Image {
        id: desktopShot

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false

        source: {
            const name = root.screen?.name ?? "";
            if (!name)
                return "";
            return `file://${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ambxst-lock/${name}.png`;
        }
    }

    // The blur is applied here rather than as desktopShot's layer.effect so the
    // result is a real item: a layer effect is skipped when an item feeds a
    // shader.
    MultiEffect {
        anchors.fill: parent

        source: desktopShot
        autoPaddingEnabled: false
        blurEnabled: true
        blur: root.blurAmount
        blurMax: 64
        blurMultiplier: 1
    }

    // The padlock overlay. In the original this is an ordinary Hyprland window
    // sitting over the desktop, so closing it runs the compositor's own
    // windowsOut animation - `style = "gnomed"` in Horizon's animations.lua -
    // with appearance.lua's rounding 15 and its 3px 45-degree primary->white
    // border drawn around it. A session-lock surface gets none of that, so the
    // shrink, the border and the fade are reproduced here.
    //
    // Only this group scales. The captured desktop behind it stays put, the way
    // the real desktop does behind a closing window - scaling that too would
    // pull the whole screen in and uncover black around it.
    Item {
        id: overlay

        anchors.fill: parent

        scale: 1 - (1 - root.outAlpha) * 0.07
        opacity: root.outAlpha
        // Flattened only while shrinking, so the fade applies to the composite
        // rather than to each layer separately.
        layer.enabled: root.outAlpha < 1

        // The scrim the padlock arrives over, 60% black in the original. It
        // eases back once the composition is up, where the blur does the work.
        Rectangle {
            anchors.fill: parent

            color: "black"
            opacity: root.introEase * 0.6 - root.reveal * 0.35
        }

        // Above the scrim, not under it: in the original the scrim belongs to
        // the prelock window and hyprlock's widgets sit over it, so the darkening
        // only ever applies to the wallpaper. Under the scrim the avatar - the
        // one element here that is a photo rather than a bright accent colour -
        // came out visibly dimmed.
        //
        // Inside this group so the composition is part of what shrinks on
        // unlock, though `reveal` has already faded it out by the time the
        // shrink starts.
        Content {
            anchors.fill: parent
            visible: Config.lock.enabled && root.cardScreen

            lock: root
            opacity: root.reveal
        }

        Padlock {
            anchors.fill: parent
            visible: Config.lock.enabled && root.cardScreen

            progress: root.introProgress
            contentScale: root.contentScale
            opacity: 1 - root.reveal
        }

        // The closing window's border: a fullscreen window has none until it
        // starts shrinking, so this appears only with the scale.
        Shape {
            anchors.fill: parent

            preferredRendererType: Shape.CurveRenderer
            visible: root.outAlpha < 1

            ShapePath {
                id: closeBorder

                readonly property real thickness: 3 * root.contentScale
                readonly property real corner: 15 * root.contentScale

                strokeWidth: 0
                fillRule: ShapePath.OddEvenFill

                fillGradient: LinearGradient {
                    x1: 0
                    y1: 0
                    x2: overlay.width
                    y2: overlay.height

                    GradientStop {
                        position: 0
                        color: Colours.palette.m3primary
                    }
                    GradientStop {
                        position: 1
                        color: "white"
                    }
                }

                PathRectangle {
                    width: overlay.width
                    height: overlay.height
                    radius: closeBorder.corner
                }

                PathRectangle {
                    x: closeBorder.thickness
                    y: closeBorder.thickness
                    width: overlay.width - closeBorder.thickness * 2
                    height: overlay.height - closeBorder.thickness * 2
                    radius: Math.max(0, closeBorder.corner - closeBorder.thickness)
                }
            }
        }
    }
}
