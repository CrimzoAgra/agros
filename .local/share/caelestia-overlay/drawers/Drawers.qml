pragma ComponentBehavior: Bound

// caelestia-overlay (split_windows): each screen's shell in four windows (PartWindow.qml) instead of Caelestia's one
// full-screen window: the left one (the bar and its popouts), the right one (sidebar, session, OSD, notifications,
// utilities, toasts), the top one (dashboard) and the bottom one (launcher), between them covering the border. Each is
// as big as what's open in it (its stretch of the border, plus its open panels), so a panel sliding in redraws its own
// window, not the whole screen: Caelestia's redrew 2560x1440, in the shell and in Hyprland (with the blur under it),
// every frame of every animation. One Controller.qml does for the four what Caelestia's Interactions.qml did

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar as Bar

Variants {
    model: Screens.screens

    Scope {
        id: scope

        required property ShellScreen modelData

        readonly property ScreenState screenState: ShellState.forScreen(modelData)
        readonly property HyprlandMonitor monitor: Hypr.monitorFor(modelData)
        readonly property var config: left?.contentItem?.Config ?? null
        readonly property real screenW: modelData?.width ?? 0
        readonly property real screenH: modelData?.height ?? 0
        readonly property real border: config?.border.thickness ?? 0

        // How thick a window is with nothing of it open: the border, its rounded inner corners and the shadow, and the
        // band Caelestia takes the pointer in to drag panels out on an empty workspace
        readonly property real edge: border + Math.max(64, left.dragMaskPadding + 16)
        // (window sizes in steps, so a panel growing a little doesn't resize its window every frame)
        function step(v: real): real {
            return Math.ceil(v / 64) * 64;
        }

        // The screen's panels, wherever their window: Caelestia's Panels.qml's names (the controller's, the launcher's)
        QtObject {
            id: shared

            readonly property Bar.BarWrapper bar: barWrapper
            readonly property var osd: rightPanels.osd
            readonly property var osdWrapper: rightPanels.osdWrapper
            readonly property var notifications: rightPanels.notifications
            readonly property var session: rightPanels.session
            readonly property var sessionWrapper: rightPanels.sessionWrapper
            readonly property var utilities: rightPanels.utilities
            readonly property var toasts: rightPanels.toasts
            readonly property var sidebar: rightPanels.sidebar
            readonly property var dashboard: topPanels?.dashboard ?? null
            readonly property var launcher: bottomPanels?.launcher ?? null
            readonly property var popoutsWrapper: leftPanels?.popoutsWrapper ?? null
            readonly property var popouts: leftPanels?.popouts ?? null
        }

        Controller {
            id: ctl

            screen: scope.modelData
            screenState: scope.screenState
            panels: shared
            config: scope.config
            bar: barWrapper
            borderThickness: left.borderLayoutThickness
            fullscreen: left.shellHidden
        }

        // How big each window needs to be for what's open in it now. The left and right ones are the screen's height;
        // the top and bottom ones the width between them
        readonly property real leftNeeded: {
            const popouts = leftPanels.popouts;
            const bar = Math.max(barWrapper.contentWidth, config?.border.minThickness ?? 0);
            const open = popouts && (popouts.hasCurrent || leftPanels.popoutsWrapper.width > 0) ? step(popouts.nonAnimWidth) : 0;
            return bar + edge - border + open;
        }
        readonly property real rightNeeded: {
            const p = shared;
            if (!p.sidebar || !p.notifications || !p.utilities || !p.session || !p.osd || !p.toasts)
                return edge;
            const sidebar = p.sidebar.offsetScale < 1 ? p.sidebar.width : 0;
            const widest = Math.max(p.notifications.visible ? p.notifications.width : 0, p.utilities.offsetScale < 1 ? p.utilities.implicitWidth : 0,
                sidebar + (p.session.offsetScale < 1 ? p.session.implicitWidth : 0) + (p.osd.offsetScale < 1 ? p.osd.implicitWidth : 0),
                p.toasts.implicitHeight > 0 ? p.sidebar.width + p.toasts.width + 40 : 0);
            return edge + (widest > 0 ? step(widest) : 0);
        }
        readonly property real topNeeded: edge + (shared.dashboard?.visible ? step(shared.dashboard.nonAnimHeight) : 0)
        readonly property real bottomNeeded: edge + (shared.launcher?.visible ? step(shared.launcher.implicitHeight) : 0)

        // ...which is the part of the border each one draws (and takes the pointer in): the left and right ones the
        // screen's height and as wide as their windows, the top and bottom ones the width between them. Kept as they are:
        // a part moving (as a panel opened) had both windows draw that stretch's shadow for a moment, a darker flash.
        // Only when the dashboard or the launcher, open, reaches past the top window's part (a narrow screen) do the side
        // ones give way, as little as their own panels let them; and a detached popout, in the middle, takes the left
        // window's part across to the right one
        readonly property real centerLeft: {
            let x = screenW;
            for (const p of [shared.dashboard, shared.launcher])
                if (p?.visible)
                    x = Math.min(x, barWrapper.implicitWidth + p.x - 64);
            return x;
        }
        readonly property real centerRight: {
            let x = 0;
            for (const p of [shared.dashboard, shared.launcher])
                if (p?.visible)
                    x = Math.max(x, barWrapper.implicitWidth + p.x + p.width + 64);
            return x;
        }
        readonly property real ownRight: Math.max(rightNeeded, Math.min(rightArea.width, screenW - centerRight))
        readonly property real ownLeft: leftPanels.popouts?.isDetached ? screenW - ownRight : Math.max(leftNeeded, Math.min(leftArea.width, centerLeft))
        readonly property rect leftOwn: Qt.rect(0, 0, ownLeft, screenH)
        readonly property rect rightOwn: Qt.rect(screenW - ownRight, 0, ownRight, screenH)
        readonly property rect topOwn: Qt.rect(ownLeft, 0, Math.max(0, screenW - ownLeft - ownRight), topArea.height)
        readonly property rect bottomOwn: Qt.rect(ownLeft, screenH - bottomArea.height, Math.max(0, screenW - ownLeft - ownRight), bottomArea.height)

        // How big each window is: room for its panels from the start, grown when something needs more, never shrunk.
        // A window resized as a panel opened or closed showed its old picture at the new size for a frame (a flicker);
        // one that isn't redrawing costs nothing however big, so it keeps its room. The windows overlap: each draws only
        // its part (PartWindow.qml)
        property real leftHeld
        property real rightHeld
        property real topHeld
        property real bottomHeld
        onLeftNeededChanged: leftHeld = Math.max(leftHeld, leftNeeded)
        onRightNeededChanged: rightHeld = Math.max(rightHeld, rightNeeded)
        onTopNeededChanged: topHeld = Math.max(topHeld, topNeeded)
        onBottomNeededChanged: bottomHeld = Math.max(bottomHeld, bottomNeeded)
        Component.onCompleted: {
            leftHeld = Math.max(leftNeeded, Math.min(screenW / 3, leftNeeded + 512));
            // (the sidebar's width is a setting, known while it's closed: the right window as wide as it, or the utilities
            // panel; rarer and wider, toasts beside the open sidebar, grow it once)
            rightHeld = Math.max(rightNeeded, edge + step(Math.max(shared.sidebar?.width || 448, shared.utilities?.implicitWidth ?? 0)));
            topHeld = Math.max(topNeeded, Math.min(screenH / 2, edge + 640));
            bottomHeld = Math.max(bottomNeeded, Math.min(screenH / 2, edge + 640));
        }

        // (a detached popout is in the middle of the screen: the left window as wide as the screen while it's there)
        readonly property rect leftArea: Qt.rect(0, 0, leftPanels.popouts?.isDetached ? screenW : Math.min(leftHeld, screenW), screenH)
        readonly property rect rightArea: Qt.rect(screenW - Math.min(rightHeld, screenW), 0, Math.min(rightHeld, screenW), screenH)
        readonly property rect topArea: Qt.rect(0, 0, screenW, Math.min(topHeld, screenH))
        readonly property rect bottomArea: Qt.rect(0, screenH - Math.min(bottomHeld, screenH), screenW, Math.min(bottomHeld, screenH))

        Exclusions {
            screen: scope.modelData
            bar: barWrapper
        }

        // ---- Left: the bar and its popouts ----
        PartWindow {
            id: left

            part: "left"
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.leftArea
            own: scope.leftOwn
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active

            regions: [
                PartRegion {
                    win: left
                    panel: leftPanels.popoutsWrapper
                    width: panel.width * (1 - leftPanels.popoutsWrapper.offsetScale)
                }
            ]

            blobs: [
                PartBg {
                    id: popoutBg

                    // Extra width to prevent vertical movement deformation partially detaching panel from bar
                    property real extraWidth: leftPanels.popouts.isDetached ? 0 : 0.2

                    win: left
                    panel: leftPanels.popoutsWrapper
                    deformAmount: leftPanels.popouts.isDetached ? 0.05 : leftPanels.popouts.hasCurrent ? 0.15 : 0.1
                    x: (leftPanels.popoutsWrapper?.x ?? 0) + (leftPanels.popouts?.x ?? 0) + left.barWidth - (leftPanels.popouts?.width ?? 0) * extraWidth
                    implicitWidth: (leftPanels.popouts?.width ?? 0) * (1 + extraWidth)

                    Behavior on extraWidth {
                        Anim {}
                    }
                }
            ]

            PanelsEdge {
                id: leftPanels

                part: "left"
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: left.borderThickness
                panels: shared

                deform: popoutBg.deformMatrix
            }

            Bar.BarWrapper {
                id: barWrapper

                anchors.top: parent.top
                anchors.bottom: parent.bottom

                screen: scope.modelData
                screenState: scope.screenState
                popouts: leftPanels.popouts

                fullscreen: left.shellHidden
            }
        }

        // ---- Right: sidebar, session, OSD, notifications, utilities, toasts ----
        PartWindow {
            id: right

            part: "right"
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.rightArea
            own: scope.rightOwn
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active
            // Over a fullscreen window: a notification, the volume popup, a toast
            showsOverFullscreen: rightPanels.notifications.visible || rightPanels.osd.offsetScale < 1 || rightPanels.toasts.implicitHeight > 0
            wantsKeyboard: scope.screenState.launcher || scope.screenState.session

            regions: [
                PartRegion {
                    id: sessionRegion

                    win: right
                    panel: rightPanels.sessionWrapper
                    x: scope.screenW - width - right.area.x
                    width: panel.width * (1 - rightPanels.session.offsetScale) + scope.border + sidebarRegion.width
                },
                PartRegion {
                    id: sidebarRegion

                    win: right
                    panel: rightPanels.sidebar
                    x: scope.screenW - width - right.area.x
                    width: panel.width * (1 - rightPanels.sidebar.offsetScale) + scope.border
                },
                PartRegion {
                    win: right
                    panel: rightPanels.osdWrapper
                    x: scope.screenW - width - right.area.x
                    width: panel.width * (1 - rightPanels.osd.offsetScale) + scope.border + sessionRegion.width
                },
                PartRegion {
                    win: right
                    panel: rightPanels.notifications
                    y: -right.area.y
                    height: panel.height + scope.border
                },
                PartRegion {
                    win: right
                    panel: rightPanels.utilities
                    y: scope.screenH - height - right.area.y
                    height: panel.height * (1 - rightPanels.utilities.offsetScale) + scope.border
                }
            ]

            // Fullscreen: the notifications and the volume popup take the pointer (Caelestia's emptyRegion)
            hiddenRegions: [
                Region {
                    x: rightPanels.notifications.x + right.barWidth - right.area.x
                    y: rightPanels.notifications.y + right.borderThickness - right.area.y
                    width: rightPanels.notifications.width
                    height: rightPanels.notifications.height
                },
                Region {
                    x: scope.screenW - width - right.area.x
                    y: rightPanels.osdWrapper.y + right.borderThickness - right.area.y
                    width: rightPanels.osdWrapper.width * (1 - rightPanels.osd.offsetScale) + right.borderThickness
                    height: rightPanels.osd.height
                }
            ]

            blobs: [
                PartBg {
                    id: sessionBg

                    win: right
                    panel: rightPanels.sessionWrapper
                    deformAmount: 0.2
                    x: rightPanels.sessionWrapper.x + rightPanels.session.x + right.barWidth
                    implicitWidth: rightPanels.session.width
                    implicitHeight: rightPanels.session.offsetScale < 1 ? rightPanels.sessionWrapper.height : 0
                },
                PartBg {
                    id: sidebarBg

                    win: right
                    panel: rightPanels.sidebar
                    deformAmount: 0.03
                    implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
                    exclude: rightPanels.sidebar.offsetScale > 0.08 || rightPanels.utilities.offsetScale > 0.08 ? [] : [utilsBg]
                    bottomLeftRadius: Math.max(0, Math.min(1, Math.max(rightPanels.sidebar.offsetScale, rightPanels.utilities.offsetScale) / 0.3)) * radius
                },
                PartBg {
                    id: osdBg

                    win: right
                    panel: rightPanels.osdWrapper
                    deformAmount: 0.25
                    x: rightPanels.osdWrapper.x + rightPanels.osd.x + right.barWidth
                    implicitWidth: rightPanels.osd.width
                    implicitHeight: rightPanels.osd.offsetScale < 1 && rightPanels.sidebar.offsetScale === 1 ? rightPanels.osdWrapper.height : 0
                },
                PartBg {
                    id: notifsBg

                    win: right
                    panel: rightPanels.notifications
                },
                PartBg {
                    id: utilsBg

                    win: right
                    panel: rightPanels.utilities
                    deformAmount: rightPanels.sidebar.visible ? 0.1 : 0.15
                    exclude: rightPanels.sidebar.offsetScale > 0.08 || rightPanels.utilities.offsetScale > 0.08 ? [] : [sidebarBg]
                    topLeftRadius: Math.max(0, Math.min(1, Math.max(rightPanels.sidebar.offsetScale, rightPanels.utilities.offsetScale) / 0.3)) * radius
                }
            ]

            PanelsRight {
                id: rightPanels

                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: right.borderThickness
                popouts: leftPanels.popouts

                utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
                utilities.deformMatrix: utilsBg.rawDeformMatrix

                session.transform: Matrix4x4 {
                    matrix: sessionBg.deformMatrix
                }
                sidebar.transform: Matrix4x4 {
                    matrix: sidebarBg.deformMatrix
                }
                osd.transform: Matrix4x4 {
                    matrix: osdBg.deformMatrix
                }
                notifications.transform: Matrix4x4 {
                    matrix: notifsBg.deformMatrix
                }
                utilities.transform: Matrix4x4 {
                    matrix: utilsBg.deformMatrix
                }
            }
        }

        // ---- Top: the dashboard ----
        PartWindow {
            id: top

            part: "top"
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.topArea
            own: scope.topOwn
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active

            regions: [
                PartRegion {
                    win: top
                    panel: topPanels.dashboard
                    y: -top.area.y
                    height: panel.height * (1 - topPanels.dashboard.offsetScale) + scope.border
                }
            ]

            blobs: [
                PartBg {
                    id: dashBg

                    win: top
                    panel: topPanels.dashboard
                    deformAmount: 0.1
                }
            ]

            PanelsEdge {
                id: topPanels

                part: "top"
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: top.borderThickness
                panels: shared

                deform: dashBg.deformMatrix
            }
        }

        // ---- Bottom: the launcher ----
        PartWindow {
            id: bottom

            part: "bottom"
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.bottomArea
            own: scope.bottomOwn
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active
            wantsKeyboard: scope.screenState.launcher || scope.screenState.session

            regions: [
                PartRegion {
                    win: bottom
                    panel: bottomPanels.launcher
                    y: scope.screenH - height - bottom.area.y
                    height: panel.height * (1 - bottomPanels.launcher.offsetScale) + scope.border
                }
            ]

            blobs: [
                PartBg {
                    id: launcherBg

                    win: bottom
                    panel: bottomPanels.launcher
                    deformAmount: 0.1
                }
            ]

            PanelsEdge {
                id: bottomPanels

                part: "bottom"
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: bottom.borderThickness
                panels: shared

                deform: launcherBg.deformMatrix
            }
        }

        // ---- Window peek's pictures and the snapping preview: full-screen windows, there only while shown ----
        StyledWindow {
            name: "drawers"
            screen: scope.modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            // (its own state, not its item's visible: an item's in a hidden window)
            visible: peek.wins.length > 0 || peek.opacity > 0

            PeekLayer {
                id: peek

                monitor: scope.monitor
            }
        }

        StyledWindow {
            name: "drawers"
            screen: scope.modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            visible: snap.shown || snap.opacity > 0

            SnapPreview {
                id: snap

                monitor: scope.monitor
            }
        }

        // The screen's shell holds the pointer while a menu is open: a click outside it closes them (Caelestia's, for
        // the four windows)
        HyprlandFocusGrab {
            id: focusGrab

            active: {
                const s = scope.screenState;
                const conf = scope.config;
                if (!conf || !shared.popouts)
                    return false;
                if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                    return true;
                if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                    return true;
                if (shared.popouts.hasCurrent && shared.popouts.currentName === "barmenu")
                    return true; // caelestia-overlay: a click outside Caelestia closes the bar's menu
                if (shared.popouts.currentName.startsWith("traymenu") && (shared.popouts.current as StackView)?.depth > 1)
                    return true;
                return false;
            }
            windows: [left, right, top, bottom]
            onCleared: {
                scope.screenState.launcher = false;
                scope.screenState.session = false;
                scope.screenState.sidebar = false;
                scope.screenState.dashboard = false;
                shared.popouts.hasCurrent = false;
                barWrapper.closeTray();
            }
        }

        // A window going fullscreen closes what's open; the whole shell hidden closes what was opened from the Super menu
        Connections {
            function onHasFullscreenChanged(): void {
                scope.screenState.launcher = false;
                scope.screenState.session = false;
                scope.screenState.dashboard = false;
                shared.popouts.close();
            }

            function onShellHiddenChanged(): void {
                if (!left.shellHidden)
                    return;
                scope.screenState.session = false;
                scope.screenState.dashboard = false;
                shared.popouts.close();
            }

            target: left
        }

        ShellState.ComponentRef {
            screen: scope.modelData
            slot: "rootWindow"
            component: left
        }

        ShellState.ComponentRef {
            screen: scope.modelData
            slot: "interactionWrapper"
            component: left.interactions
        }

        ShellState.ComponentRef {
            screen: scope.modelData
            slot: "bar"
            component: barWrapper
        }

        ShellState.ComponentRef {
            screen: scope.modelData
            slot: "panels"
            component: shared
        }
    }
}
