pragma ComponentBehavior: Bound

// caelestia-overlay: AgrOS's settings (AgrosSettings.qml's) as Nexus sections: the groups of dots-settings's pages
// pageIds, each a section header and a row for each setting (AgrosRow.qml). On an AgrOS page all of its groups; folded
// into one of Nexus's own pages, only what Nexus doesn't show itself: only the groups in onlyGroups (when given), not
// the ones in skipGroups, nor the settings in skipKeys, nor Caelestia's
// options Nexus's pages set (covered: written in by patch.py's nexus_pages, from Nexus's pages as they are). Over them,
// why the last change failed, and when the shell will restart for one. Kept row by row as the schema is read again
// (each change does), so a switch isn't redrawn in the middle of moving

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
    property bool notice: true
    property bool firstHeader: true
    // (Caelestia's options, by their path in its shell.json, that Nexus's own pages set)
    readonly property var covered: []
    // (the kinds AgrosRow.qml has a control for)
    readonly property list<string> kinds: ["bool", "choice", "number", "text", "startup", "image", "keys"]
    readonly property var groups: {
        const out = [];
        for (const id of pageIds)
            for (const g of AgrosSettings.page(id)?.groups ?? []) {
                if (skipGroups.includes(g.title ?? "") || onlyGroups.length && !onlyGroups.includes(g.title ?? ""))
                    continue;
                const keys = (g.settings ?? []).filter(s => kinds.includes(s.type) && !skipKeys.includes(s.key) && !(s.key.startsWith("caelestia-shell.") && covered.includes(s.key.slice(16)))).map(s => s.key);
                if (keys.length)
                    out.push({ title: g.title ?? "", keys });
            }
        return out;
    }

    spacing: Tokens.spacing.extraSmall / 2

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

    Repeater {
        model: ScriptModel {
            values: root.groups.map(g => g.title)
        }

        ColumnLayout {
            id: group

            required property string modelData
            required property int index
            readonly property var keys: root.groups.find(g => g.title === modelData)?.keys ?? []

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader {
                first: root.firstHeader && group.index === 0
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
