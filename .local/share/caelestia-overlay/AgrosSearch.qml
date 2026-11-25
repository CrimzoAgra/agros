pragma ComponentBehavior: Bound

// caelestia-overlay: Nexus's search, its results (in the page's place while two letters or more are typed): AgrOS's
// settings (AgrosSettings.qml's) whose name, what they do or key has what's typed, by the page they're on, each a row
// to change it right there; a group's header opens its page. Each setting once (Advanced's list of Caelestia's options
// repeats the ones on other pages: found there first), the first 60. The nav list keeps the pages it finds (Nexus's own
// pages' settings are found by their page)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string typed: nState.searchText.trim().toLowerCase()
    // (what's typed, a moment after the last key: not a new list on each letter)
    property string query
    readonly property list<string> kinds: ["bool", "choice", "number", "text", "startup", "image", "keys", "json"]
    readonly property var groups: {
        const q = query;
        if (q.length < 2)
            return [];
        const has = t => String(t ?? "").toLowerCase().includes(q);
        const out = [], seen = {};
        let n = 0;
        for (const p of AgrosSettings.pages)
            for (const g of p.groups ?? []) {
                const keys = (g.settings ?? []).filter(s => !seen[s.key] && kinds.includes(s.type) && (has(s.label) || has(s.description) || has(s.key))).map(s => s.key);
                keys.forEach(k => seen[k] = true);
                if (!keys.length || n >= 60)
                    continue;
                const nav = PageRegistry.pages.findIndex(np => (np.agros ?? []).includes(p.id));
                out.push({
                    title: `${nav >= 0 ? PageRegistry.pages[nav].label : p.title} › ${g.title}`,
                    nav,
                    keys: keys.slice(0, 60 - n)
                });
                n += keys.length;
            }
        return out;
    }

    title: "Search"
    onTypedChanged: settle.restart()
    Component.onCompleted: query = typed

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // (in the column: the page's one child is its content)
        Timer {
            id: settle

            interval: 200
            onTriggered: root.query = root.typed
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.query.length >= 2 && !root.groups.length
            text: AgrosSettings.loaded ? "No setting has that in its name. The pages that do are in the list on the left." : "Reading the settings…"
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
            wrapMode: Text.Wrap
        }

        Repeater {
            model: ScriptModel {
                values: root.groups
            }

            ColumnLayout {
                id: group

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                // Its page's name and the group's: a click opens the page (the search cleared)
                RowLayout {
                    Layout.fillWidth: true

                    SectionHeader {
                        Layout.fillWidth: true
                        first: group.index === 0
                        text: group.modelData.title
                    }

                    MaterialIcon {
                        visible: group.modelData.nav >= 0
                        text: "arrow_forward"
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    TapHandler {
                        enabled: group.modelData.nav >= 0
                        onTapped: {
                            root.nState.currentPageIdx = group.modelData.nav;
                            root.nState.clearSearch();
                        }
                    }

                    HoverHandler {
                        enabled: group.modelData.nav >= 0
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Repeater {
                    model: group.modelData.keys

                    AgrosRow {
                        required property string modelData
                        required property int index

                        key: modelData
                        first: index === 0
                        last: index === group.modelData.keys.length - 1
                    }
                }
            }
        }
    }
}
