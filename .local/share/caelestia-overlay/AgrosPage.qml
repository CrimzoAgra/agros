pragma ComponentBehavior: Bound

// caelestia-overlay: one of AgrOS's settings pages in Nexus (dots-settings's schema page pageId: AgrosSettings.qml), its
// groups as Nexus sections, each setting a row (AgrosRow.qml). Kept row by row as the schema is read again (each change
// does), so a switch isn't redrawn in the middle of moving

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    required property string pageId
    readonly property var page: AgrosSettings.page(pageId)
    // (the kinds AgrosRow.qml has a control for)
    readonly property list<string> kinds: ["bool", "choice", "number", "text"]

    Component.onCompleted: AgrosSettings.reload()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Repeater {
            model: ScriptModel {
                values: (root.page?.groups ?? []).map(g => g.title ?? "")
            }

            ColumnLayout {
                id: group

                required property string modelData
                required property int index
                readonly property var keys: ((root.page?.groups ?? []).find(g => (g.title ?? "") === modelData)?.settings ?? [])
                    .filter(s => root.kinds.includes(s.type)).map(s => s.key)

                Layout.fillWidth: true
                visible: keys.length > 0
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: group.index === 0
                    text: group.modelData
                }

                Repeater {
                    model: ScriptModel {
                        values: group.keys
                    }

                    AgrosRow {
                        required property string modelData
                        required property int index

                        key: modelData
                        first: index === 0
                        last: index === group.keys.length - 1
                    }
                }
            }
        }
    }
}
