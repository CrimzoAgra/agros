pragma Singleton

// caelestia-overlay: a window being dragged, as AgrOS's config tells it (~/.config/caelestia/user/windows.lua, through
// Hyprland's custom events): "agros_drag 1" / "agros_drag 0" while any window is moved or resized (the panels don't
// open from the edges meanwhile, nor the bar's popouts: Interactions.qml), and "agros_snap <screen> x y w h" /
// "agros_snap none" for where a moved window would snap if let go now (SnapPreview.qml draws it)

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool dragging
    property string snapScreen
    property rect snapBox

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "custom")
                return;
            const f = event.data.split(" ");
            if (f[0] === "agros_drag") {
                root.dragging = f[1] === "1";
                if (!root.dragging)
                    root.snapScreen = "";
            } else if (f[0] === "agros_snap") {
                if (f.length === 6) {
                    root.snapBox = Qt.rect(+f[2], +f[3], +f[4], +f[5]);
                    root.snapScreen = f[1];
                } else {
                    root.snapScreen = "";
                }
            }
        }

        target: Hyprland
    }
}
