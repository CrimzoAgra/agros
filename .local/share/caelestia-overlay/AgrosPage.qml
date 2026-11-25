pragma ComponentBehavior: Bound

// caelestia-overlay: one of AgrOS's settings pages in Nexus (dots-settings's schema page pageId: AgrosSettings.qml),
// its groups as Nexus sections (AgrosSections.qml)

import QtQuick
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    required property string pageId
    // (Advanced: Caelestia's options not on another page, its groups closed)
    property bool advanced

    Component.onCompleted: AgrosSettings.reload()

    AgrosSections {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        pageIds: [root.pageId]
        skipListed: root.advanced
        foldOver: root.advanced ? 0 : -1
    }
}
