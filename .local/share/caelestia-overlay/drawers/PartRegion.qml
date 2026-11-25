// caelestia-overlay (split_windows): a panel's input rectangle in one of the shell's windows (win, PartWindow.qml), from screen
// coordinates (Caelestia's Regions.qml's R): added to the window's part of the border

import QtQuick
import Quickshell
import Caelestia.Blobs
import Caelestia.Config

Region {
    required property PartWindow win
    required property Item panel

    x: (panel?.x ?? 0) + win.barWidth - win.area.x
    y: (panel?.y ?? 0) + win.contentItem.Config.border.thickness - win.area.y
    width: panel?.width ?? 0
    height: panel?.height ?? 0
    intersection: Intersection.Combine
}
