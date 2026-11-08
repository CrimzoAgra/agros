pragma ComponentBehavior: Bound

// caelestia-overlay: popout for a hovered dock icon (see modules/bar/components/Dock.qml)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

ColumnLayout {
    id: root

    required property PopoutState popouts
    readonly property var dock: popouts.dockItem
    // The hovered icon as the dock has it now (a window opened or closed meanwhile)
    readonly property var target: dock?.items.find(i => i.uid === popouts.dockTarget?.uid) ?? popouts.dockTarget
    readonly property var wins: target?.wins ?? []
    readonly property bool several: wins.length > 1
    // The hovered icon went away (its only window closed): the popout goes too, not left showing it
    readonly property bool gone: popouts.currentName === "dock" && !!dock && !!popouts.dockTarget && !dock.items.some(i => i.uid === popouts.dockTarget.uid)

    onGoneChanged: if (gone) done()

    // A window being closed: no preview of it (Dock.closeSoon)
    // (as the dock's own: a Steam game with no shortcut, its icon from Steam's cache, else Steam's)
    function steamIcon(cls: string): string {
        const game = cls.match(/^steam_app_(\d+)$/);
        if (!game)
            return "";
        return Quickshell.iconPath(`steam_icon_${game[1]}`, true) ? `steam_icon_${game[1]}` : "steam";
    }

    // A window's preview size, fitted in w x h as the preview fits it: known before its first frame arrives (until then
    // the preview was an empty w x h box, and the menu jumped to the window's shape a frame later, on every open)
    function fit(win: var, w: real, h: real): size {
        const s = win?.lastIpcObject?.size ?? [w, h];
        const k = Math.min(w / Math.max(1, s[0]), h / Math.max(1, s[1]));
        return Qt.size(Math.round(s[0] * k), Math.round(s[1] * k));
    }

    function shows(win: var): bool {
        return !!win && !(dock?.closing ?? []).includes(win.address);
    }
    readonly property string appId: target?.entry?.id ?? ""
    readonly property bool favourite: appId !== "" && Strings.testRegexList(GlobalConfig.launcher.favouriteApps, appId)

    function done(): void {
        popouts.hasCurrent = false;
    }

    // Its original width; the window's preview is scaled to fit it (the workspace preview is as wide: WorkspacePreview.qml).
    // The name and title don't widen it (they're cut short instead)
    width: 280
    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.topMargin: Tokens.padding.small
        spacing: Tokens.spacing.medium

        IconImage {
            asynchronous: true
            Layout.alignment: Qt.AlignVCenter
            implicitSize: details.implicitHeight
            // (a game with no Steam shortcut: Steam's icon, as in the dock)
            source: Quickshell.iconPath(root.target?.entry?.icon ?? root.steamIcon(root.target?.win?.lastIpcObject.class ?? ""), "application-x-executable")
        }

        ColumnLayout {
            id: details

            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                // (a window with no app entry, e.g. a game without a Steam shortcut: by its title)
                text: root.target?.entry?.name ?? (root.target?.win?.lastIpcObject.title || root.target?.win?.lastIpcObject.class) ?? ""
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                // (not the title again when it's the name above; several windows: how many, their titles are below)
                text: root.several ? qsTr("%1 windows").arg(root.wins.length) : root.target?.entry ? (root.target?.win?.title || (root.target?.pinned ? qsTr("Pinned, not running") : "")) : ""
                visible: text !== ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }
    }

    ClippingWrapperRectangle {
        visible: !!root.target?.win && !root.several
        color: "transparent"
        radius: Tokens.rounding.medium
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: size.width
        Layout.preferredHeight: size.height

        readonly property size size: root.fit(root.target?.win, root.width, root.width)

        ScreencopyView {
            id: preview

            captureSource: !root.several && root.shows(root.target?.win) ? root.target.win.wayland : null // qmllint disable unresolved-type
            live: visible

            // Fitted to the menu's width (a tall window: as tall as that, at most)
            constraintSize.width: root.width
            constraintSize.height: root.width

            // A click on the preview does what clicking the dock icon does: that window, to the front
            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: {
                    root.dock?.focusWindow(root.target.win);
                    root.done();
                }
            }
        }
    }

    // Several windows: each one's preview (two side by side from three on) with its title; a click brings it up
    GridLayout {
        id: grid

        visible: root.several
        Layout.fillWidth: true
        columns: root.wins.length > 2 ? 2 : 1
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.small

        Repeater {
            // Tiles kept as windows come and go (not all rebuilt)
            model: ScriptModel {
                values: root.several ? root.wins : []
                objectProp: "address"
            }

            ColumnLayout {
                id: tile

                required property var modelData
                readonly property real tileWidth: (root.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns

                Layout.preferredWidth: tileWidth
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacing.small / 2
                opacity: tile.modelData.workspace?.name?.startsWith("special:minimised") ? 0.6 : 1  // minimised

                ClippingWrapperRectangle {
                    color: "transparent"
                    radius: Tokens.rounding.small
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: size.width
                    Layout.preferredHeight: size.height

                    readonly property size size: root.fit(tile.modelData, tile.tileWidth, tile.tileWidth * 0.6)

                    ScreencopyView {
                        captureSource: root.shows(tile.modelData) ? tile.modelData.wayland : null // qmllint disable unresolved-type
                        live: visible
                        constraintSize.width: tile.tileWidth
                        constraintSize.height: tile.tileWidth * 0.6

                        StateLayer {
                            radius: Tokens.rounding.small
                            onClicked: {
                                root.dock?.focusWindow(tile.modelData);
                                root.done();
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small / 2

                    StyledText {
                        Layout.fillWidth: true
                        text: tile.modelData.title || tile.modelData.lastIpcObject?.class || ""
                        color: tile.modelData.activated ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    // This window only (the menu stays: the others are still there)
                    Item {
                        implicitWidth: closeIcon.implicitWidth + Tokens.padding.small
                        implicitHeight: closeIcon.implicitHeight + Tokens.padding.small / 2

                        StateLayer {
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3error
                            onClicked: root.dock?.closeSoon([tile.modelData])
                        }

                        MaterialIcon {
                            id: closeIcon

                            anchors.centerIn: parent
                            text: "close"
                            color: Colours.palette.m3error
                        }
                    }
                }
            }
        }
    }

    Action {
        visible: !!root.target?.entry
        icon: "push_pin"
        filled: !!root.target?.pinned
        label: root.target?.pinned ? qsTr("Unpin from dock") : qsTr("Pin to dock")
        onTriggered: root.dock?.togglePin(root.target.key)
    }

    Action {
        visible: root.appId !== ""
        icon: "favorite"
        filled: root.favourite
        label: root.favourite ? qsTr("Remove from favourites") : qsTr("Add to favourites")
        onTriggered: {
            const apps = GlobalConfig.launcher.favouriteApps;
            GlobalConfig.launcher.favouriteApps = root.favourite ? apps.filter(a => !Strings.testRegexList([a], root.appId)) : [...apps, root.appId]; // patterns too
        }
    }

    Action {
        visible: !!root.target?.entry
        icon: "open_in_new"
        label: root.target?.win ? qsTr("New window") : qsTr("Open")
        onTriggered: Apps.launch(root.target.entry)
    }

    Action {
        visible: !!root.target?.win
        icon: "close"
        label: root.several ? qsTr("Close all windows") : qsTr("Close window")
        danger: true
        onTriggered: root.dock?.closeSoon(root.wins)
    }

    // For apps that ignore "Close window" or hang (e.g. a game that won't exit): kill its process
    Action {
        visible: (root.target?.win?.lastIpcObject.pid ?? 0) > 0
        icon: "dangerous"
        label: qsTr("Force quit")
        danger: true
        onTriggered: {
            // Its previews let go first (Dock.closeSoon's reason), then the kill
            // (only that process's windows: the app's others can be other processes)
            const pid = root.target.win.lastIpcObject.pid;
            root.dock?.forgetSoon(root.wins.filter(w => w.lastIpcObject?.pid === pid));
            Quickshell.execDetached(["sh", "-c", `sleep 0.4; kill -9 ${pid}`]);
        }
    }

    component Action: Item {
        id: action

        required property string icon
        required property string label
        property bool filled
        property bool danger

        signal triggered

        Layout.fillWidth: true
        implicitWidth: actionRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: actionRow.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            radius: Tokens.rounding.full
            color: action.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
            onClicked: {
                action.triggered();
                root.done();
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
                fill: action.filled ? 1 : 0
                color: action.danger ? Colours.palette.m3error : action.filled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: action.label
                color: action.danger ? Colours.palette.m3error : Colours.palette.m3onSurface
            }
        }
    }
}
