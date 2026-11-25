// caelestia-overlay: recording a shortcut for one of AgrOS's (AgrosSettings.qml's capture, started by a shortcut row's
// + in AgrosRow.qml), over all of Nexus (Nexus.qml): the keys pressed, as Hyprland names them, are added to it. One
// needs Super, Ctrl or Alt (F keys, Print and Pause may go alone); Caelestia's "mod + 0-9" ones take modifiers alone,
// recorded as they're let go. Esc or a click cancels

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Rectangle {
    id: root

    property var held: []

    visible: !!AgrosSettings.capture
    color: Qt.rgba(0, 0, 0, 0.6)
    radius: Tokens.rounding.large
    focus: visible
    onVisibleChanged: if (visible) forceActiveFocus()

    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape && !event.modifiers)
            return AgrosSettings.endCapture("");
        if (AgrosSettings.isModifierKey(event.key)) {
            held = AgrosSettings.modifiers(event.modifiers);
            return;
        }
        if (!AgrosSettings.capture.modifier) {
            const mods = AgrosSettings.modifiers(event.modifiers);
            const k = event.key;
            const alone = (k >= Qt.Key_F1 && k <= Qt.Key_F35) || k === Qt.Key_Print || k === Qt.Key_Pause;
            if (!alone && !mods.some(m => m !== "SHIFT"))
                return AgrosSettings.captureHint = "Hold Super, Ctrl or Alt with it";
            AgrosSettings.endCapture([...mods, AgrosSettings.keyName(event)].join(" + "));
        }
    }
    Keys.onReleased: event => {
        event.accepted = true;
        if (AgrosSettings.capture?.modifier && AgrosSettings.isModifierKey(event.key) && held.length) {
            // Shift alone would take Shift + 1-0 (!, @...) from typing
            if (!held.some(m => m !== "SHIFT"))
                return AgrosSettings.captureHint = "Shift alone would stop !, @... being typed: add Super, Ctrl or Alt";
            AgrosSettings.endCapture(held.join(" + "));
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: AgrosSettings.endCapture("")
    }

    StyledRect {
        anchors.centerIn: parent
        implicitWidth: Math.max(420, box.implicitWidth + Tokens.padding.extraLarge * 2)
        implicitHeight: box.implicitHeight + Tokens.padding.extraLarge * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh

        ColumnLayout {
            id: box

            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "keyboard"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AgrosSettings.capture?.modifier ? "Press and let go of the modifier keys" : "Press the new shortcut"
                font: Tokens.font.title.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AgrosSettings.captureHint || "Esc or a click cancels"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }
        }
    }
}
