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
        // The bar's edge (bar_side in patch.py sets this, by the Settings app's bar.side): left, right, top or bottom.
        // On the right: everything laid out as with it on the left, then mirrored. Sizes and parts are worked out as for
        // a left bar (in "virtual" x, the screen seen in a mirror); each window's place, and anything placed by x in
        // screen coordinates, mirrored back. Along the top or bottom (across): its window a strip there, holding that
        // edge's middle panel too (the dashboard under a top bar, the launcher over a bottom one: they come out of the
        // bar), that panel's own window the left border's column instead; the right window as before
        readonly property string barEdge: "left" // bar_side
        readonly property bool barRight: barEdge === "right"
        readonly property bool barTop: barEdge === "top"
        readonly property bool barBottom: barEdge === "bottom"
        readonly property bool barAcross: barTop || barBottom
        // (a rect, mirrored across the screen when the bar is on the right)
        function mr(r: rect): rect {
            return barRight ? Qt.rect(screenW - r.x - r.width, r.y, r.width, r.height) : r;
        }
        // (a panel's x in its inner area (the screen less the bar and border), as it'd be with the bar on the left)
        function vx(p: Item): real {
            return barRight ? screenW - barWrapper.implicitWidth - border - p.x - p.width : p.x;
        }
        // (where the inner area starts, in virtual x: after the bar, or the left border with the bar across)
        readonly property real innerX: barAcross ? border : barWrapper.implicitWidth
        // (the x, in a window, of something width wide against the screen's edge away from the bar: the right one with
        // the bar on the left)
        function edgeX(width: real, win: PartWindow): real {
            return (barRight ? 0 : screenW - width) - win.area.x;
        }

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
            // (the bar across: a top bar's notification centre and pop-ups, a bottom bar's utilities, in the left
            // border's window: PanelsLeft.qml)
            readonly property var notifications: topLeftPanels?.notifications ?? rightPanels.notifications
            readonly property var session: rightPanels.session
            readonly property var sessionWrapper: rightPanels.sessionWrapper
            readonly property var utilities: bottomLeftPanels?.utilities ?? rightPanels.utilities
            readonly property var toasts: rightPanels.toasts
            readonly property var sidebar: topLeftPanels?.sidebar ?? rightPanels.sidebar
            readonly property var dashboard: topPanels?.dashboard ?? barPanels?.dashboard ?? null
            readonly property var launcher: bottomPanels?.launcher ?? barPanels?.launcher ?? null
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
            barEdge: scope.barEdge
            borderThickness: left.borderLayoutThickness
            fullscreen: left.shellHidden
        }

        // How big each window needs to be for what's open in it now. The left and right ones are the screen's height;
        // the top and bottom ones the width between them
        readonly property real leftNeeded: {
            const popouts = leftPanels.popouts;
            const bar = Math.max(barWrapper.contentWidth, config?.border.minThickness ?? 0);
            if (barAcross) {
                // (across: how deep, with the popouts and the panel it holds under or over it)
                const open = popouts && (popouts.hasCurrent || leftPanels.popoutsWrapper.height > 0) ? step(popouts.nonAnimHeight) : 0;
                const m = barPanels.dashboard ?? barPanels.launcher;
                const held = m?.visible ? step(barPanels.dashboard ? m.nonAnimHeight : m.implicitHeight) : 0;
                return bar + edge - border + Math.max(open, held);
            }
            const open = popouts && (popouts.hasCurrent || leftPanels.popoutsWrapper.width > 0) ? step(popouts.nonAnimWidth) : 0;
            return bar + edge - border + open;
        }
        readonly property real rightNeeded: {
            const p = rightPanels;
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
        // (the middle panels of the top and bottom windows: with the bar across, the one not in the bar's window)
        readonly property var stripPanels: barTop ? [shared.launcher] : barBottom ? [shared.dashboard] : [shared.dashboard, shared.launcher]
        readonly property real centerLeft: {
            let x = screenW;
            for (const p of stripPanels)
                if (p?.visible)
                    x = Math.min(x, innerX + vx(p) - 64);
            return x;
        }
        readonly property real centerRight: {
            let x = 0;
            for (const p of stripPanels)
                if (p?.visible)
                    x = Math.max(x, innerX + vx(p) + p.width + 64);
            return x;
        }
        readonly property bool detached: leftPanels.popouts?.isDetached ?? false
        readonly property real ownRight: Math.max(rightNeeded, Math.min(rightArea.width, screenW - centerRight))
        // (across: the left border's column, as wide as a window with nothing open)
        // (across: the left border's column, as wide as its window, to where the middle panel is)
        readonly property real ownLeft: barAcross ? Math.max(columnNeeded, Math.min(columnArea.width, centerLeft)) : detached ? screenW - ownRight : Math.max(leftNeeded, Math.min(leftArea.width, centerLeft))
        readonly property rect leftOwn: barAcross ? barOwn : Qt.rect(0, 0, ownLeft, screenH)
        // (the screen's height always, the bar across too: something of the bar's reaching over the column (barInCorner)
        // has the bar's window, above it, draw that corner over its part, not take it: given back, a part Qt didn't
        // draw again, the border black there on a narrow screen till something else in the window changed)
        readonly property rect rightOwn: Qt.rect(screenW - ownRight, 0, ownRight, screenH)
        readonly property rect topOwn: barTop ? columnOwn : barBottom && detached ? Qt.rect(screenW - ownRight, 0, 0, topArea.height) : middleOwn(shared.dashboard, 0, topArea.height)
        readonly property rect bottomOwn: barBottom ? columnOwn : barTop && detached ? Qt.rect(screenW - ownRight, screenH - bottomArea.height, 0, bottomArea.height) : middleOwn(shared.launcher, screenH - bottomArea.height, bottomArea.height)

        // A middle window's part: between the columns, and as wide as its panel (and its corners' room) whatever the
        // columns still hold: drawn over them there. A panel opening where one in a column is still closing (a narrow
        // screen: the dashboard as the utilities panel goes) had no background over that column till it had closed
        function middleOwn(p: Item, y: real, h: real): rect {
            let l = ownLeft, r = screenW - ownRight;
            if (p?.visible) {
                l = Math.min(l, innerX + vx(p) - 64);
                r = Math.max(r, innerX + vx(p) + p.width + 64);
            }
            l = Math.max(0, l);
            return Qt.rect(l, y, Math.max(0, Math.min(screenW, r) - l), h);
        }

        // The bar across: its window's part the strip along its edge, as deep as its window, between the left border's
        // column and the right window's (both the screen's height, the bar's ends included: its window, over theirs, has
        // the pointer all along it); with something of it open reaching over one of them (a popout under the bar's end,
        // the dashboard under the clock), across that column too, as deep as what's open, drawn over the column's part
        // there (the same border under it). The other middle panel's window between the two columns. A detached popout:
        // the bar's window everything but the right column
        readonly property real barOpenLeft: {
            const w = leftPanels.popoutsWrapper;
            let l = w && w.width > 0 && w.height > 0 ? border + w.x : screenW;
            const m = barPanels.dashboard ?? barPanels.launcher;
            if (m?.visible)
                l = Math.min(l, border + m.x);
            return l;
        }
        readonly property real barOpenRight: {
            const w = leftPanels.popoutsWrapper;
            let r = w && w.width > 0 && w.height > 0 ? border + w.x + w.width : 0;
            const m = barPanels.dashboard ?? barPanels.launcher;
            if (m?.visible)
                r = Math.max(r, border + m.x + m.width);
            return r;
        }
        readonly property bool barInCorner: barAcross && !detached && barOpenRight + (config?.border.rounding ?? 0) > screenW - ownRight
        readonly property bool barInLeftCorner: barAcross && !detached && barOpenLeft - (config?.border.rounding ?? 0) < ownLeft
        readonly property real barOwnDepth: barInCorner || barInLeftCorner ? Math.min(leftNeeded, barArea.height) : barArea.height
        readonly property rect barOwn: {
            if (detached)
                return Qt.rect(0, 0, screenW - ownRight, screenH);
            // (at least 1 px wide: a narrow screen's columns can be wider than it together, a part below 0 wide)
            const x = barInLeftCorner ? 0 : Math.min(ownLeft, screenW - 1);
            return Qt.rect(x, barTop ? 0 : screenH - barOwnDepth, Math.max(1, (barInCorner ? screenW : screenW - ownRight) - x), barOwnDepth);
        }
        readonly property rect columnOwn: detached ? Qt.rect(0, barTop ? screenH : 0, ownLeft, 0) : Qt.rect(0, 0, ownLeft, screenH)
        // (how wide the column needs to be: its panels open, PanelsLeft.qml's)
        readonly property real columnNeeded: {
            const c = barTop ? topLeftPanels : bottomLeftPanels;
            let w = 0;
            if (c?.notifications?.visible)
                w = c.notifications.width;
            if (c?.sidebar && c.sidebar.offsetScale < 1)
                w = Math.max(w, c.sidebar.width);
            if (c?.utilities && c.utilities.offsetScale < 1)
                w = Math.max(w, c.utilities.implicitWidth);
            return edge + (w > 0 ? step(w) : 0);
        }
        property real columnHeld
        onColumnNeededChanged: columnHeld = Math.max(columnHeld, columnNeeded)

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
            leftHeld = Math.max(leftNeeded, Math.min(barAcross ? screenH / 2 : screenW / 3, leftNeeded + 512));
            // (the sidebar's width is a setting, known while it's closed: the right window as wide as it, or the utilities
            // panel; rarer and wider, toasts beside the open sidebar, grow it once)
            rightHeld = Math.max(rightNeeded, edge + step(Math.max(shared.sidebar?.width || 448, shared.utilities?.implicitWidth ?? 0)));
            topHeld = Math.max(topNeeded, Math.min(screenH / 2, edge + 640));
            // (across: as wide as the panels it takes, known closed)
            columnHeld = Math.max(columnNeeded, barAcross ? edge + step(Math.max(rightPanels.sidebar?.width || 448, rightPanels.utilities?.implicitWidth ?? 0)) : edge);
            bottomHeld = Math.max(bottomNeeded, Math.min(screenH / 2, edge + 640));
        }

        // (a detached popout is in the middle of the screen: the left window as wide as the screen while it's there)
        readonly property rect leftArea: barAcross ? barArea : Qt.rect(0, 0, detached ? screenW : Math.min(leftHeld, screenW), screenH)
        readonly property rect rightArea: Qt.rect(screenW - Math.min(rightHeld, screenW), 0, Math.min(rightHeld, screenW), screenH)
        readonly property rect topArea: barTop ? columnArea : Qt.rect(0, 0, screenW, Math.min(topHeld, screenH))
        readonly property rect bottomArea: barBottom ? columnArea : Qt.rect(0, screenH - Math.min(bottomHeld, screenH), screenW, Math.min(bottomHeld, screenH))
        // (across: the bar's window a strip along its edge, the whole screen with a detached popout; the left border's)
        readonly property rect barArea: detached ? Qt.rect(0, 0, screenW, screenH) : Qt.rect(0, barTop ? 0 : screenH - Math.min(leftHeld, screenH), screenW, Math.min(leftHeld, screenH))
        readonly property rect columnArea: Qt.rect(0, 0, Math.min(columnHeld, screenW), screenH)

        // (a top bar: the dashboard, in the bar's window, drops down under the clock that opened it (bar_side's change to
        // Bar.qml); opened otherwise (its shortcut), in the middle. Its middle's screen x, -1 for the screen's)
        property real dashAt: -1

        Connections {
            function onDashboardChanged(): void {
                if (scope.screenState.dashboard)
                    scope.dashAt = scope.barTop && ctl.containsMouse && ctl.mouseY < barWrapper.implicitWidth ? (leftPanels.popouts?.currentCenter ?? -1) : -1;
            }

            target: scope.screenState
        }

        Exclusions {
            screen: scope.modelData
            bar: barWrapper
        }

        // ---- Left: the bar and its popouts ----
        PartWindow {
            id: left

            part: "left"
            barEdge: scope.barEdge
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.mr(scope.leftArea)
            own: scope.mr(scope.leftOwn)
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active
            // (a bottom bar: the launcher's in this window)
            wantsKeyboard: scope.barBottom && (scope.screenState.launcher || scope.screenState.session)
            // (across: over the right window, whose part has the bar's far end, and the pointer all along the bar)
            above: scope.barAcross

            regions: [
                PartRegion {
                    win: left
                    panel: leftPanels.popoutsWrapper
                    width: scope.barAcross ? panel.width : panel.width * (1 - leftPanels.popoutsWrapper.offsetScale)
                },
                Region {
                    x: -left.area.x
                    y: (scope.barBottom ? scope.screenH - height : 0) - left.area.y
                    width: scope.barAcross ? scope.screenW : 0
                    height: barWrapper.implicitWidth
                },
                // (across: the panel of the bar's edge, from that edge, over the bar, to where it's out)
                PartRegion {
                    win: left
                    panel: barPanels.dashboard ?? barPanels.launcher
                    y: scope.barBottom ? scope.screenH - height - left.area.y : -left.area.y
                    height: (panel?.height ?? 0) * (1 - ((barPanels.dashboard ?? barPanels.launcher)?.offsetScale ?? 1)) + barWrapper.implicitWidth
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
                    x: (leftPanels.popoutsWrapper?.x ?? 0) + (leftPanels.popouts?.x ?? 0) + left.innerLeft - (scope.barRight || scope.barAcross ? 0 : (leftPanels.popouts?.width ?? 0) * extraWidth)
                    implicitWidth: (leftPanels.popouts?.width ?? 0) * (scope.barAcross ? 1 : 1 + extraWidth)
                    // (across: the popout as it slides, and taller into the bar instead)
                    y: (leftPanels.popoutsWrapper?.y ?? 0) + left.innerTop + (scope.barAcross ? (leftPanels.popouts?.y ?? 0) - (scope.barTop ? (leftPanels.popouts?.height ?? 0) * extraWidth : 0) : 0)
                    implicitHeight: scope.barAcross ? (leftPanels.popouts?.height ?? 0) * (1 + extraWidth) : (leftPanels.popoutsWrapper?.height ?? 0)

                    Behavior on extraWidth {
                        Anim {}
                    }
                },
                PartBg {
                    id: barPanelBg

                    win: left
                    panel: barPanels.dashboard ?? barPanels.launcher
                    deformAmount: 0.1
                }
            ]

            PanelsEdge {
                id: leftPanels

                part: "left"
                barEdge: scope.barEdge
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: left.borderThickness
                panels: shared

                deform: popoutBg.deformMatrix
            }

            // (across: the dashboard under a top bar, the launcher over a bottom one)
            PanelsEdge {
                id: barPanels

                part: scope.barTop ? "top" : scope.barBottom ? "bottom" : "none"
                barEdge: scope.barEdge
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: left.borderThickness
                panels: shared
                dashboardAt: scope.dashAt

                deform: barPanelBg.deformMatrix
            }

            Bar.BarWrapper {
                id: barWrapper

                // (across: a strip along the top or bottom, as thick as its implicitWidth, whichever its edge)
                x: scope.barRight ? parent.width - width : 0
                y: scope.barBottom ? parent.height - height : 0
                width: scope.barAcross ? parent.width : implicitWidth
                height: scope.barAcross ? implicitWidth : parent.height

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
            barEdge: scope.barEdge
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.mr(scope.rightArea)
            own: scope.mr(scope.rightOwn)
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
                    x: scope.edgeX(width, right)
                    width: panel.width * (1 - rightPanels.session.offsetScale) + scope.border + sidebarRegion.width
                },
                PartRegion {
                    id: sidebarRegion

                    win: right
                    panel: rightPanels.sidebar
                    x: scope.edgeX(width, right)
                    width: panel.width * (1 - rightPanels.sidebar.offsetScale) + scope.border
                },
                PartRegion {
                    win: right
                    panel: rightPanels.osdWrapper
                    x: scope.edgeX(width, right)
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
                    x: rightPanels.notifications.x + right.innerLeft - right.area.x
                    y: rightPanels.notifications.y + right.borderThickness - right.area.y
                    width: rightPanels.notifications.width
                    height: rightPanels.notifications.height
                },
                Region {
                    x: scope.edgeX(width, right)
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
                    x: rightPanels.sessionWrapper.x + rightPanels.session.x + right.innerLeft
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
                    bottomLeftRadius: rightPanels.sidebar.meetsUtilities ? Math.max(0, Math.min(1, Math.max(rightPanels.sidebar.offsetScale, rightPanels.utilities.offsetScale) / 0.3)) * radius : radius
                },
                PartBg {
                    id: osdBg

                    win: right
                    panel: rightPanels.osdWrapper
                    deformAmount: 0.25
                    x: rightPanels.osdWrapper.x + rightPanels.osd.x + right.innerLeft
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
                    topLeftRadius: rightPanels.sidebar.meetsUtilities ? Math.max(0, Math.min(1, Math.max(rightPanels.sidebar.offsetScale, rightPanels.utilities.offsetScale) / 0.3)) * radius : radius
                }
            ]

            PanelsRight {
                id: rightPanels

                barEdge: scope.barEdge
                away: scope.barTop ? "notifs" : scope.barBottom ? "utilities" : ""
                awaySidebar: topLeftPanels.sidebar
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
            barEdge: scope.barEdge
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.mr(scope.topArea)
            own: scope.mr(scope.topOwn)
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active

            // (a top bar: the left border's column, the notification centre and its pop-ups in it)
            showsOverFullscreen: topLeftPanels.notifications?.visible ?? false

            regions: [
                PartRegion {
                    win: top
                    panel: topPanels.dashboard
                    y: -top.area.y
                    height: (panel?.height ?? 0) * (1 - (topPanels.dashboard?.offsetScale ?? 1)) + scope.border
                },
                // (from the screen's bottom edge up)
                PartRegion {
                    win: top
                    panel: topLeftPanels.notifications
                    height: (panel?.height ?? 0) + scope.border
                },
                PartRegion {
                    win: top
                    panel: topLeftPanels.sidebar
                    x: -top.area.x
                    width: (panel?.width ?? 0) * (1 - (topLeftPanels.sidebar?.offsetScale ?? 1)) + scope.border
                }
            ]

            hiddenRegions: [
                Region {
                    x: (topLeftPanels.notifications?.x ?? 0) + top.innerLeft - top.area.x
                    y: (topLeftPanels.notifications?.y ?? 0) + top.innerTop - top.area.y
                    width: topLeftPanels.notifications?.width ?? 0
                    height: topLeftPanels.notifications?.height ?? 0
                }
            ]

            blobs: [
                PartBg {
                    id: dashBg

                    win: top
                    panel: topPanels.dashboard
                    deformAmount: 0.1
                },
                PartBg {
                    id: leftNotifsBg

                    win: top
                    panel: topLeftPanels.notifications
                },
                PartBg {
                    id: leftSidebarBg

                    win: top
                    panel: topLeftPanels.sidebar
                    deformAmount: 0.03
                }
            ]

            PanelsLeft {
                id: topLeftPanels

                part: scope.barTop ? "notifs" : "none"
                barEdge: scope.barEdge
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: top.borderThickness
                others: rightPanels
                popouts: leftPanels.popouts

                deform: leftNotifsBg.deformMatrix
                sidebarDeform: leftSidebarBg.deformMatrix
            }

            PanelsEdge {
                id: topPanels

                part: scope.barTop ? "none" : "top"
                barEdge: scope.barEdge
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
            barEdge: scope.barEdge
            screen: scope.modelData
            monitor: scope.monitor
            area: scope.mr(scope.bottomArea)
            own: scope.mr(scope.bottomOwn)
            controller: ctl
            bar: barWrapper
            grabActive: focusGrab.active
            wantsKeyboard: !scope.barBottom && (scope.screenState.launcher || scope.screenState.session)

            regions: [
                PartRegion {
                    win: bottom
                    panel: bottomPanels.launcher
                    y: scope.screenH - height - bottom.area.y
                    height: (panel?.height ?? 0) * (1 - (bottomPanels.launcher?.offsetScale ?? 1)) + scope.border
                },
                // (a bottom bar: the left border's column, the utilities panel in it, from the screen's top edge down)
                PartRegion {
                    win: bottom
                    panel: bottomLeftPanels.utilities
                    y: -bottom.area.y
                    height: Math.max(0, (panel?.y ?? 0) + (panel?.height ?? 0)) + scope.border
                }
            ]

            blobs: [
                PartBg {
                    id: launcherBg

                    win: bottom
                    panel: bottomPanels.launcher
                    deformAmount: 0.1
                },
                PartBg {
                    id: leftUtilsBg

                    win: bottom
                    panel: bottomLeftPanels.utilities
                    deformAmount: 0.15
                }
            ]

            PanelsLeft {
                id: bottomLeftPanels

                part: scope.barBottom ? "utilities" : "none"
                barEdge: scope.barEdge
                screen: scope.modelData
                screenState: scope.screenState
                bar: barWrapper
                borderThickness: bottom.borderThickness
                others: rightPanels
                popouts: leftPanels.popouts

                deform: leftUtilsBg.deformMatrix
                rawDeform: leftUtilsBg.rawDeformMatrix
            }

            PanelsEdge {
                id: bottomPanels

                part: scope.barBottom ? "none" : "bottom"
                barEdge: scope.barEdge
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
