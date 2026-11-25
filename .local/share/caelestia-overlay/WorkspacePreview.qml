// caelestia-overlay: the bar's workspace preview (hovering a workspace): a miniature of its screen with live pictures of
// its windows where they are, like the active window popout's. Shown by Bar.qml's checkPopout for workspaces with
// windows (the workspace_preview patch in patch.py); a click switches to it
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Column {
    id: root

    required property PopoutState popouts

    readonly property HyprlandWorkspace workspace: Hypr.workspaces.values.find(w => w.id === popouts.previewWs) ?? null
    readonly property var mon: workspace?.monitor?.lastIpcObject ?? null
    // The monitor in logical pixels (what window positions are in), shrunk to the preview's width
    // (width and height of its mode, swapped on a screen turned sideways)
    readonly property bool turned: (mon?.transform ?? 0) % 2 === 1
    readonly property real monW: mon ? (turned ? mon.height : mon.width) / mon.scale : 1920
    readonly property real monH: mon ? (turned ? mon.width : mon.height) / mon.scale : 1080
    // 280 px wide, the dock menu's width (DockMenu.qml): smaller than Caelestia's own previews (400)
    readonly property real factor: 280 / monW
    // Its screen's own wallpaper, set in Settings (screens.<its description>.wallpaper in settings.json, as the
    // background's), else the one for every screen
    property var settings: ({})
    readonly property string wallpaper: {
        const own = settings[`screens.${workspace?.monitor?.description ?? ""}.wallpaper`];
        return typeof own === "string" && own !== "" ? own : Wallpapers.current;
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.config/dots/settings.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const all = JSON.parse(text());
                root.settings = all && typeof all === "object" ? all : {};
            } catch (e) {
                root.settings = {};
            }
        }
        onLoadFailed: root.settings = {}
    }

    spacing: Tokens.spacing.medium

    StyledText {
        text: qsTr("Workspace %1").arg(root.workspace?.name || root.popouts.previewWs) // (its name: the 2nd screen's 11 is "1")
        font: Tokens.font.body.medium
    }

    ClippingRectangle {
        implicitWidth: root.monW * root.factor
        implicitHeight: root.monH * root.factor
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3surfaceContainerHigh

        // The wallpaper behind, as on screen (and as in the Super+Tab switcher's previews): its screen's, by
        // its own file (a URL of the fixed link to it kept the old picture in the image cache after a change), each part
        // encoded ("#", "%"); a video wallpaper (Caelestia's coming ones) isn't a picture: its still that Caelestia keeps
        Image {
            property string failedFor

            anchors.fill: parent
            source: root.wallpaper ? (failedFor === root.wallpaper ? `file://${Paths.state}/wallpaper/thumbnail.jpg` : `file://${root.wallpaper.split("/").map(encodeURIComponent).join("/")}`) : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 400
            asynchronous: true
            cache: true
            onStatusChanged: if (status === Image.Error) failedFor = root.wallpaper
        }

        // Floating windows last, so they're drawn on top like on screen. Each window keeps its live picture as the list
        // changes (every title change refreshes it): rebuilding them all at once crashed the shell
        Repeater {
            model: ScriptModel {
                values: (root.workspace?.toplevels.values ?? []).filter(t => t.lastIpcObject?.mapped).sort((a, b) => (a.lastIpcObject.floating ? 1 : 0) - (b.lastIpcObject.floating ? 1 : 0))
                objectProp: "address"
            }

            ClippingRectangle {
                id: win

                required property HyprlandToplevel modelData
                readonly property var ipc: modelData.lastIpcObject

                x: ((ipc.at?.[0] ?? 0) - (root.mon?.x ?? 0)) * root.factor
                y: ((ipc.at?.[1] ?? 0) - (root.mon?.y ?? 0)) * root.factor
                width: (ipc.size?.[0] ?? 0) * root.factor
                height: (ipc.size?.[1] ?? 0) * root.factor
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHighest

                ScreencopyView {
                    id: winPreview

                    anchors.fill: parent
                    captureSource: win.modelData.wayland // qmllint disable unresolved-type
                    // A snapshot as it shows, then one a second: live, every frame of the window was copied as long as it
                    // showed (and hovering along the dock opened one after another), keeping the GPU busy
                    live: false

                    Timer {
                        running: root.visible && !!winPreview.captureSource
                        repeat: true
                        interval: 1000
                        onTriggered: winPreview.captureFrame()
                    }
                    constraintSize.width: win.width
                    constraintSize.height: win.height
                }
            }
        }

        // A click goes to the workspace
        StateLayer {
            radius: Tokens.rounding.medium
            onClicked: {
                // Both screens to their column (user/workspaces.lua), as Super+N does; Caelestia's switches only this one
                Quickshell.execDetached(["hyprctl", "eval", `dots.goto_workspace(${root.popouts.previewWs})`]);
                root.popouts.hasCurrent = false;
            }
        }
    }
}
