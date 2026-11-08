pragma ComponentBehavior: Bound

// caelestia-overlay: the bar's right-click menu (see the bar_menu patch in patch.py)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property PopoutState popouts

    // The desktop's window mode: user/windows.lua keeps it in this file (floating unless it says tiling)
    property bool tiling: false

    width: 220
    spacing: Tokens.spacing.small

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/window-mode`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.tiling = text().trim() === "tiling"
    }

    Action {
        icon: "monitoring"
        label: qsTr("Task Manager")
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "dots.task_manager()"]) // as Ctrl+Shift+Esc: btop
    }

    // Every window floats or tiles, and new ones follow (dots.toggle_window_mode in user/windows.lua)
    Action {
        icon: root.tiling ? "filter_none" : "grid_view"
        label: root.tiling ? qsTr("Switch to floating") : qsTr("Switch to tiling")
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "dots.toggle_window_mode()"])
    }

    // The same rows as the dock's menu (DockMenu.qml)
    component Action: Item {
        id: action

        required property string icon
        required property string label

        signal triggered

        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.small
        Layout.bottomMargin: Tokens.padding.small
        implicitHeight: actionRow.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            radius: Tokens.rounding.full
            onClicked: {
                action.triggered();
                root.popouts.hasCurrent = false;
            }
        }

        RowLayout {
            id: actionRow

            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: action.icon
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: action.label
                color: Colours.palette.m3onSurface
            }
        }
    }
}
