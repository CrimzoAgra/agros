// caelestia-overlay (split_windows): the pointer over one of a screen's shell windows (PartWindow.qml), told to the
// screen's Controller.qml, which does what Caelestia's Interactions.qml did. Full-screen and shifted by where its window
// is (as everything in it), so the pointer's place is in screen coordinates; the panels and the bar go inside it, as in
// Caelestia's (a panel's own areas under the pointer, this one still sees it)

import QtQuick
import qs.components
import qs.components.controls

CustomMouseArea {
    id: root

    required property Controller controller

    function onWheel(event: WheelEvent): void {
        controller.wheel(event);
    }

    acceptedButtons: controller.fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true

    onPressedChanged: controller.pressed = pressed
    onPressed: event => controller.press(event.x, event.y, event.button)
    onContainsMouseChanged: controller.setInside(root, containsMouse)
    onPositionChanged: event => controller.move(event.x, event.y)
    Component.onDestruction: controller.setInside(root, false)
}
