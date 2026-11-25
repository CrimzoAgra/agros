pragma ComponentBehavior: Bound

// caelestia-overlay (nexus_pages): Settings' Panels › Taskbar › Dock, beside Caelestia's own component pages: the
// AgrOS dock's own switches (its patches, AgrosRow.qml as everywhere: turning one off rebuilds the shell)

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: "Dock"
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        AgrosRow {
            first: true
            key: "caelestia.dock"
        }

        AgrosRow {
            key: "caelestia.dock_space"
        }

        AgrosRow {
            last: true
            key: "caelestia.window_peek"
        }
    }
}
