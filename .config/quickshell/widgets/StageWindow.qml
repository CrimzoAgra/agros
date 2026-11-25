// One piece of a screen's widget stage (shell.qml) in a window of its own: area is the piece's rectangle in stage
// coordinates, what's drawn past its items included, and the window is that size, where the stage puts it. A change in
// one piece (the clock's second, a glitch, the media's progress) has Hyprland redraw and blur behind that piece only:
// one full-screen window had it redo the whole screen, and every animation in the shell above redid the blur behind
// all of it. (A file of its own: Quickshell doesn't take a PanelWindow as an inline component)

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: piece

    // The screen's stage: x, y (its top-left corner on the screen), width, height (1920x1080) and fit (its scale)
    required property QtObject stage
    property rect area
    default property alias content: inner.data

    anchors { top: true; left: true }
    margins.left: Math.round(stage.x + area.x * stage.fit)
    margins.top: Math.round(stage.y + area.y * stage.fit)
    implicitWidth: Math.ceil(area.width * stage.fit)
    implicitHeight: Math.ceil(area.height * stage.fit)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "desktop-widgets"
    color: "transparent"
    mask: Region {}

    // The whole stage, scaled, shifted so this piece's area is the window
    Item {
        id: inner

        x: piece.stage.x - piece.margins.left
        y: piece.stage.y - piece.margins.top
        width: piece.stage.width
        height: piece.stage.height
        scale: piece.stage.fit
        transformOrigin: Item.TopLeft
    }
}
