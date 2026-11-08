pragma ComponentBehavior: Bound

// caelestia-overlay: window peek's pictures (WindowPeek.qml), for windows on a workspace not being shown (another one,
// or minimised): in the drawers' window under the border, the bar and its popouts, each window live where it is, over
// the real desktop (wallpaper and widgets: Hyprland fades out the windows there meanwhile). On the screen they're on,
// faded in and out. Takes no input (the drawers' input region is unchanged)

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

Item {
    id: root

    required property HyprlandMonitor monitor

    // The windows shown, when they're on this screen; the last ones kept while fading out
    readonly property var wins: WindowPeek.picturedOn === monitor ? WindowPeek.pictured : []
    property var last: []
    readonly property var mon: monitor?.lastIpcObject ?? null

    onWinsChanged: {
        if (wins.length > 0)
            last = wins;
    }

    anchors.fill: parent
    opacity: wins.length > 0 ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    // Tiled windows first, then floating ones from the least to the most recently focused: on top as on screen
    Repeater {
        model: ScriptModel {
            values: root.visible ? [...root.last].sort((a, b) => {
                const fa = a.lastIpcObject?.floating ? 1 : 0, fb = b.lastIpcObject?.floating ? 1 : 0;
                return fa !== fb ? fa - fb : (b.lastIpcObject?.focusHistoryID ?? 0) - (a.lastIpcObject?.focusHistoryID ?? 0);
            }) : []
            objectProp: "address"
        }

        // The window, where it is on its screen (window positions are the layout's, in logical pixels, as this window is)
        ScreencopyView {
            id: pic

            required property HyprlandToplevel modelData
            readonly property var ipc: modelData.lastIpcObject

            x: (ipc?.at?.[0] ?? 0) - (root.mon?.x ?? 0)
            y: (ipc?.at?.[1] ?? 0) - (root.mon?.y ?? 0)
            captureSource: modelData.wayland // qmllint disable unresolved-type
            live: root.visible
            constraintSize.width: ipc?.size?.[0] ?? 0
            constraintSize.height: ipc?.size?.[1] ?? 0
            // Drawn through a layer of its own, so a see-through window (a terminal's background) is blended over what's
            // behind it: drawn straight, its capture's alpha went through to the screen, a hole through the shell
            layer.enabled: true
        }
    }
}
