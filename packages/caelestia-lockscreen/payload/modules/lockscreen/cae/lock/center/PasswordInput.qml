pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import M3Shapes
import Caelestia.Config
import qs.modules.lockscreen.cae.components
import qs.modules.lockscreen.cae.components.controls
import qs.modules.lockscreen.cae.services

StyledRect {
    id: root

    required property real centerScale
    required property int centerWidth
    required property var lock

    readonly property int outlineWidth: Math.max(2, Math.round(5 * centerScale))

    implicitWidth: {
        const w = centerWidth * 0.8;
        return lock.pam.buffer ? w : Math.min(w, inputField.placeholderWidth + iconWrapper.implicitWidth + enterButton.implicitWidth + input.spacing * 2 + Tokens.padding.medium * 2);
    }
    implicitHeight: input.implicitHeight + Tokens.padding.small

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    focus: true
    onActiveFocusChanged: {
        if (!activeFocus)
            forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (root.lock.unlocking)
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return)
            inputField.placeholder.animate = false;

        root.lock.pam.handleKey(event);
    }

    Behavior on implicitWidth {
        Anim {}
    }

    StateLayer {
        hoverEnabled: false
        cursorShape: Qt.IBeamCursor
        onClicked: parent.forceActiveFocus()
    }

    // Diagonal primary -> tertiary outline, mirroring the hyprlock field this
    // composition is modelled on. Rectangle's border takes a single colour, so
    // the ring is one odd-even filled shape - the outer pill minus the inner
    // one - with the gradient running corner to corner across it. Drawn as a
    // shape rather than a masked gradient: masking needs the mask item kept
    // rendering but off the scene, which silently degrades into drawing the
    // mask itself.
    Shape {
        anchors.fill: parent

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: ring

            readonly property real outerRadius: Math.min(root.radius, root.height / 2)

            strokeWidth: 0
            fillRule: ShapePath.OddEvenFill

            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.width
                y2: root.height

                GradientStop {
                    position: 0
                    color: Colours.palette.m3primary
                }
                GradientStop {
                    position: 1
                    color: Colours.palette.m3tertiary
                }
            }

            PathRectangle {
                width: root.width
                height: root.height
                radius: ring.outerRadius
            }

            PathRectangle {
                x: root.outlineWidth
                y: root.outlineWidth
                width: Math.max(0, root.width - root.outlineWidth * 2)
                height: Math.max(0, root.height - root.outlineWidth * 2)
                radius: Math.max(0, ring.outerRadius - root.outlineWidth)
            }
        }
    }

    RowLayout {
        id: input

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        spacing: Tokens.spacing.medium

        Item {
            id: iconWrapper

            Layout.fillHeight: true
            implicitWidth: height

            AnimLoader {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: sourceComponent === iconComp ? 1 : 0
                sourceComp: root.lock.pam.passwd.active || root.lock.pam.howdy.active ? loadingComp : iconComp
            }

            Component {
                id: iconComp

                MaterialIcon {
                    animate: true
                    text: {
                        if (root.lock.pam.fprint.tries >= GlobalConfig.lock.maxFprintTries) {
                            if (root.lock.pam.howdy.canAttempt)
                                return "face";
                            return "fingerprint_off";
                        }
                        if (root.lock.pam.fprint.active)
                            return "fingerprint";
                        if (root.lock.pam.howdy.canAttempt)
                            return "face";
                        return "lock";
                    }
                    color: !root.lock.pam.howdy.canAttempt && root.lock.pam.fprint.tries >= GlobalConfig.lock.maxFprintTries ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale).build()
                    fill: text === "face"
                }
            }

            Component {
                id: loadingComp

                LoadingIndicator {
                    implicitSize: iconWrapper.height - Tokens.padding.small * 2
                }
            }
        }

        InputField {
            id: inputField

            Layout.fillWidth: true
            Layout.fillHeight: true

            centerScale: root.centerScale
            pam: root.lock.pam
        }

        Item {
            id: enterButton

            implicitWidth: implicitHeight
            implicitHeight: {
                const h = enterIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                return h % 2 === 0 ? h : h + 1;
            }

            MaterialShape {
                anchors.fill: parent

                color: root.lock.pam.buffer ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                shape: root.lock.pam.buffer ? MaterialShape.Arrow : MaterialShape.Circle
                scale: !root.lock.pam.buffer ? 1 : mouse.pressed ? 0.6 : mouse.containsMouse ? 0.8 : 0.7
                rotation: 90

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.lock.pam.buffer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.lock.pam.buffer && root.lock.pam.passwd.start()
                }
            }

            MaterialIcon {
                id: enterIcon

                anchors.centerIn: parent
                text: "arrow_forward"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.2).build()
                opacity: root.lock.pam.buffer ? 0 : 1

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
