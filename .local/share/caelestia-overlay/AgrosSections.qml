pragma ComponentBehavior: Bound

// caelestia-overlay: AgrOS's settings (AgrosSettings.qml's) as Nexus sections: the groups of dots-settings's pages
// pageIds, each a section header and a row for each setting (AgrosRow.qml). On an AgrOS page all of its groups; folded
// into one of Nexus's own pages, only what Nexus doesn't show itself: only the groups in onlyGroups (when given), not
// the ones in skipGroups, nor the settings in skipKeys, nor Caelestia's
// options Nexus's pages set (covered: written in by patch.py's nexus_pages, from Nexus's pages as they are). Over them,
// why the last change failed, and when the shell will restart for one. On a wide page (Nexus maximised) the groups go
// in two columns, each group to the shorter one so far. Kept row by row as the schema is read again (each change
// does), so a switch isn't redrawn in the middle of moving

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    property list<string> pageIds
    property list<string> onlyGroups
    property list<string> skipGroups
    property list<string> skipKeys
    // (not the settings on another of AgrOS's pages: Advanced's, which lists Caelestia's options)
    property bool skipListed
    // (a group with more rows than this starts closed, its header opening it; -1: none)
    property int foldOver: -1
    // (a group's title as shown, by its title in the schema: "Each screen's own" for the wallpapers')
    property var retitle: ({})
    property bool notice: true
    property bool firstHeader: true
    // (Caelestia's options, by their path in its shell.json, that Nexus's own pages set)
    readonly property var covered: []
    // (the kinds AgrosRow.qml has a control for)
    readonly property list<string> kinds: ["bool", "choice", "number", "text", "startup", "image", "keys", "json"]
    readonly property var groups: {
        const out = [];
        for (const id of pageIds)
            for (const g of AgrosSettings.page(id)?.groups ?? []) {
                if (skipGroups.includes(g.title ?? "") || onlyGroups.length && !onlyGroups.includes(g.title ?? ""))
                    continue;
                const keys = (g.settings ?? []).filter(s => kinds.includes(s.type) && !skipKeys.includes(s.key) && !(skipListed && AgrosSettings.listed[s.key]) && !(s.key.startsWith("caelestia-shell.") && covered.includes(s.key.slice(16)))).map(s => s.key);
                if (keys.length)
                    out.push({
                        title: g.title ?? "",
                        keys
                    });
            }
        return out;
    }
    readonly property int columns: width >= 1300 ? 2 : 1
    // The groups' titles in each column
    readonly property var split: {
        const cols = Array.from({
            length: columns
        }, () => []), size = Array(columns).fill(0);
        for (const g of groups) {
            const i = size.indexOf(Math.min(...size));
            cols[i].push(g.title);
            size[i] += g.keys.length + 1;
        }
        return cols;
    }

    spacing: Tokens.spacing.extraSmall / 2

    // Rows waiting for the settings to be read (the first time Nexus opens)
    AgrosSkeleton {
        Layout.fillWidth: true
        visible: !AgrosSettings.loaded
        header: false
        rows: 4
    }

    // Why the last change failed; the shell's restart waiting for Settings to close
    StyledRect {
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.medium
        visible: root.notice && (AgrosSettings.error !== "" || AgrosSettings.restartHeld)
        implicitHeight: notice.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: AgrosSettings.error ? Colours.palette.m3errorContainer : Colours.palette.m3secondaryContainer

        RowLayout {
            id: notice

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: AgrosSettings.error ? "error" : "restart_alt"
                color: AgrosSettings.error ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSecondaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: AgrosSettings.error || "The shell restarts to apply this when you close Settings"
                color: AgrosSettings.error ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSecondaryContainer
                font: Tokens.font.body.small
                wrapMode: Text.Wrap
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraLarge

        Repeater {
            model: root.columns

            ColumnLayout {
                id: column

                required property int index

                Layout.fillWidth: true
                Layout.preferredWidth: 1 // (columns as wide as each other)
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacing.extraSmall / 2

                Repeater {
                    model: ScriptModel {
                        values: root.split[column.index] ?? []
                    }

                    ColumnLayout {
                        id: group

                        required property string modelData
                        required property int index
                        readonly property var keys: root.groups.find(g => g.title === modelData)?.keys ?? []
                        readonly property bool folds: root.foldOver >= 0 && keys.length > root.foldOver
                        property bool open: !folds

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall / 2

                        RowLayout {
                            Layout.fillWidth: true

                            SectionHeader {
                                Layout.fillWidth: true
                                first: root.firstHeader && group.index === 0
                                text: (root.retitle[group.modelData] ?? group.modelData) + (group.folds ? ` (${group.keys.length})` : "")
                            }

                            MaterialIcon {
                                visible: group.folds
                                text: group.open ? "expand_less" : "expand_more"
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            TapHandler {
                                enabled: group.folds
                                onTapped: group.open = !group.open
                            }

                            HoverHandler {
                                enabled: group.folds
                                cursorShape: Qt.PointingHandCursor
                            }
                        }

                        Repeater {
                            model: ScriptModel {
                                values: group.open ? group.keys : []
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
    }
}
