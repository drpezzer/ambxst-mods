pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.components
import qs.modules.globals
import qs.modules.theme
import qs.config

// BarPopout: the two forms a bar widget's popout can take, behind one handle.
//
// With "contain bar" off the bar is a row of floating pills, so a popout is a
// pill too — a BarPopup window offset from the bar, exactly as before.
//
// With it on the bar is part of the frame, and a window floating next to it
// reads as a separate object stuck to a solid band. Attached, the popout is
// instead drawn inside UnifiedShellPanel's own surface (see BarFlyout), where it
// shares the frame's fill and flares back into it with concave corners — the
// frame bulging out around the button rather than something sitting on top of
// it. That surface belongs to the shell panel, not to the bar widget, so the
// contents are handed over as a Component and instantiated there.
//
// Either way the widget declares its contents once, as a child of this:
//
//     BarPopout {
//         id: thingPopout
//         anchorItem: buttonBg
//         bar: root.bar
//         popupPadding: 16
//
//         Item {
//             implicitWidth: 220
//             implicitHeight: 132
//             ...
//         }
//     }
//
// The contents must declare their own implicitWidth/implicitHeight — that is
// what both hosts size themselves from — and are laid out at exactly that size.
Item {
    id: root

    // The bar button the popout belongs to; supplies the position it grows from.
    required property Item anchorItem
    // The bar panel, for orientation and screen.
    required property var bar

    // Gap between the popout's edge and its contents.
    property int popupPadding: 8
    // Same, attached. Popouts that draw their own cards edge-to-edge want less
    // than the floating pill gives them.
    property int flyoutPadding: popupPadding
    // StyledRect variant for the floating pill's background. Attached, the fill
    // is always the frame's own, or the seam would show.
    property string variant: "popup"

    // Contents, instantiated by whichever host is in use.
    default property Component content

    // A handle, not a visual — everything it owns is drawn elsewhere.
    width: 0
    height: 0

    readonly property bool vertical: root.bar?.orientation === "vertical"
    readonly property string screenName: root.bar?.screen?.name ?? ""

    // Attached needs a frame to merge into; without one there is nothing to
    // bulge out of and the pill is the only sensible form.
    readonly property bool attached: (Config.bar?.containBar ?? false) && (Config.bar?.frameEnabled ?? false)

    // Only one flyout exists shell-wide, so ours is open only while it is ours.
    readonly property bool flyoutOpen: GlobalStates.barFlyoutOpen && GlobalStates.barFlyoutOwner === root

    // Logical open state, as BarPopup reports it: set on intent, not when the
    // animation finishes.
    readonly property bool isOpen: root.attached ? root.flyoutOpen : pill.isOpen

    // Corner radius for contents that run edge to edge, so they nest inside the
    // host without the gap pinching at the corners. A rounded child inset by p
    // from a rounded parent of radius R only keeps an even gap all the way round
    // when its own radius is R - p; give it the parent's radius instead and the
    // ring narrows by nearly half diagonally, which reads as a wobbly border.
    // The two hosts round differently, hence the split — see BarFlyout's
    // panelRadius and BarPopup's background.
    readonly property real contentRadius: root.attached ? Math.max(0, Styling.radius(4) - root.flyoutPadding) : Math.max(0, Styling.radius(8) - root.popupPadding)

    signal closedExternally

    // Where the popout should sprout from: the centre of the button along the
    // bar axis, in panel coordinates. Read at click time — mapToItem isn't a
    // bindable dependency, so as a property binding this would silently go stale.
    // Rounded, because this ends up as the panel's own position: a bar widget
    // sized from text metrics has a fractional height, and half a pixel of it
    // lands the whole panel off-grid. Everything drawn inside then rasterises
    // asymmetrically — rounded corners pick up a flat lip at one end and lose
    // their last row at the other.
    function currentAnchor(): real {
        const p = root.anchorItem.mapToItem(null, 0, 0);
        return Math.round(root.vertical ? p.y + root.anchorItem.height / 2 : p.x + root.anchorItem.width / 2);
    }

    function open(): void {
        if (root.attached)
            GlobalStates.openBarFlyout(root, root.content, root.screenName, root.currentAnchor(), root.flyoutPadding);
        else
            pill.open();
    }

    function close(): void {
        if (root.attached) {
            if (root.flyoutOpen)
                GlobalStates.closeBarFlyout();
        } else {
            pill.close();
        }
    }

    function toggle(): void {
        if (root.isOpen)
            root.close();
        else
            root.open();
    }

    // Toggling "contain bar" swaps which host owns the contents underneath an
    // open popout, which would otherwise leave the abandoned one on screen.
    onAttachedChanged: {
        if (root.flyoutOpen)
            GlobalStates.closeBarFlyout();
        pill.close();
    }

    // Explicitly into `data`: the default property is the contents, so a plain
    // child here would be swallowed as those instead.
    data: [
        BarPopup {
            id: pill
            anchorItem: root.anchorItem
            bar: root.bar
            popupPadding: root.popupPadding
            variant: root.variant

            contentWidth: (pillContent.item?.implicitWidth ?? 0) + root.popupPadding * 2
            contentHeight: (pillContent.item?.implicitHeight ?? 0) + root.popupPadding * 2

            onClosedExternally: root.closedExternally()

            Loader {
                id: pillContent
                anchors.fill: parent
                // Attached, the contents belong to BarFlyout instead; two live
                // copies would mean two of everything behind them — two polling
                // timers, two pomodoros.
                active: !root.attached
                sourceComponent: root.content
            }
        }
    ]
}
