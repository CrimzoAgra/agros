// caelestia-overlay: where a dragged window snaps if let go now (WindowDrag.qml), as on Windows: a see-through box in
// the shell's colours, on its screen, fading in where it is and moving between zones as the pointer slides along the
// edges. In the drawers' window, under the border and the bar; takes no input (the drawers' input region is unchanged)

import QtQuick
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property HyprlandMonitor monitor
    readonly property bool shown: WindowDrag.snapScreen !== "" && WindowDrag.snapScreen === monitor?.name
    // (bound, never assigned: it follows the pointer from zone to zone along the edges; let go of, it fades out where it
    // was, as the box is kept)
    readonly property rect box: WindowDrag.snapBox

    x: box.x
    y: box.y
    width: box.width
    height: box.height
    radius: Tokens.rounding.large
    color: Qt.alpha(Colours.palette.m3primary, 0.18)
    border.width: 2
    border.color: Qt.alpha(Colours.palette.m3primary, 0.6)
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
    Behavior on x {
        enabled: root.visible

        Anim {}
    }
    Behavior on y {
        enabled: root.visible

        Anim {}
    }
    Behavior on width {
        enabled: root.visible

        Anim {}
    }
    Behavior on height {
        enabled: root.visible

        Anim {}
    }
}
