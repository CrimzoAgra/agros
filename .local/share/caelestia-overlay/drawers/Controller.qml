pragma ComponentBehavior: Bound

// caelestia-overlay (split_windows): what the pointer over a screen's shell does, for its four windows (PartWindow.qml)
// together: Caelestia's Interactions.qml (with the overlay's changes to it), moved here from the one full-screen window's
// mouse area. Each window's mouse area (Interactions.qml) tells it where the pointer is, in screen coordinates; it opens
// and closes the panels as that one area did. The pointer leaving one window for the next isn't leaving the shell: only
// when it's in none of them for a moment (leaveTimer) are the hovered panels closed

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.components
import qs.services

Scope {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    // The screen's panels, wherever their window (Drawers.qml): Caelestia's Panels.qml's names
    required property var panels
    // Caelestia's settings for this screen (a window's contentItem.Config)
    required property var config
    property var bar
    readonly property var popouts: panels?.popouts ?? null
    // The left window's (its border's layout thickness, fullscreen: shellHidden)
    property real borderThickness
    property bool fullscreen
    // The bar's edge (Drawers.qml). On the right: this works in the screen seen in a mirror, as if the bar were on the
    // left (the pointer's x mirrored as it comes in, Interactions.qml's mx; the panels' through vx), so all below is as
    // is. Along the top or bottom (across): the bar's things in the bar's own terms (across it from the screen's edge,
    // u; along it, v: what the bar's own y is, its content turned a quarter), the panels after it where they are; the
    // dashboard opens from the clock, not the top edge (a top bar), the launcher and utilities not from the bottom one
    // (a bottom bar), the notification sidebar not from the top one (a top bar)
    property string barEdge: "left"
    readonly property bool barRight: barEdge === "right"
    readonly property bool barTop: barEdge === "top"
    readonly property bool barBottom: barEdge === "bottom"
    readonly property bool across: barTop || barBottom
    // ...and where the panels the bar's edge pushes away are (PanelsLeft.qml): a top bar's notification centre at the
    // bottom-left (its hover edge the bottom one there), a bottom bar's utilities at the top-left (its corner the top one)
    readonly property bool sidebarLeft: barTop
    readonly property bool utilitiesTop: barBottom

    // (the pointer's x as it'd be with the bar on the left)
    function mx(x: real): real {
        return barRight ? width - x : x;
    }

    // (a panel's x in its inner area, as it'd be with the bar on the left)
    function vx(p: Item): real {
        return barRight ? width - bar.implicitWidth - borderThickness - p.x - p.width : p.x;
    }

    // (the inner area's start, x in the mirror and y; how far the bottom border reaches up: the bar's where it is)
    readonly property real innerX: across ? borderThickness : bar.implicitWidth
    readonly property real innerY: barTop ? bar.implicitWidth : borderThickness
    readonly property real topInset: barTop ? bar.implicitWidth : config.border.thickness
    readonly property real bottomInset: barBottom ? bar.implicitWidth : config.border.thickness

    // (a point in the bar's terms: u across it from the screen's edge, v along it)
    function bu(x: real, y: real): real {
        return barTop ? y : barBottom ? height - y : x;
    }
    function bv(x: real, y: real): real {
        return across ? x : y;
    }
    function onBar(x: real, y: real): bool {
        return bu(x, y) < bar.implicitWidth;
    }

    // The pointer: where it last was (screen coordinates), whether a button is held, whether it's over the shell
    property real mouseX
    property real mouseY
    property bool pressed
    readonly property bool containsMouse: insideAreas.length > 0 || leaveTimer.running
    property var insideAreas: []
    readonly property real width: screen.width
    readonly property real height: screen.height

    property point dragStart
    // caelestia-overlay: the sidebar's hover edge held while a notification pop-up is on screen, and until the pointer
    // that was there then leaves it (sidebarHoverOpens: whether the pointer at it, or not, opens it now)
    property bool sidebarHoverHeld

    function setInside(area: Item, inside: bool): void {
        const others = insideAreas.filter(a => a !== area);
        insideAreas = inside ? [...others, area] : others;
        if (inside)
            leaveTimer.stop();
        else if (insideAreas.length === 0)
            leaveTimer.restart();
    }

    property Timer leaveTimer: Timer {
        interval: 60
        onTriggered: root.left()
    }

    function atSidebarEdge(x: real, y: real): bool {
        if (sidebarLeft)
            return y > height - Math.max(config.border.minThickness, config.border.thickness) - config.border.rounding && withinPanelWidth(panels.sidebar, x, y) && root.edgeHover(false, y >= height - root.edgePx || root.sideShared("bottom"));
        return y < Math.max(config.border.minThickness, config.border.thickness) + config.border.rounding && withinPanelWidth(panels.sidebar, x, y) && root.edgeHover(false, y < root.edgePx || root.sideShared("top"));
    }

    // (over the open sidebar, wherever it is; the utilities panel)
    function inSidebar(x: real, y: real): bool {
        if (sidebarLeft)
            return x < innerX + panels.sidebar.x + panels.sidebar.width && withinPanelHeight(panels.sidebar, x, y);
        return inRightPanel(panels.sidebar, x, y);
    }

    function inUtilities(x: real, y: real): bool {
        return utilitiesTop ? inTopPanel(panels.utilities, x, y) : inBottomPanel(panels.utilities, x, y);
    }

    function sidebarHoverOpens(atEdge: bool): bool {
        if (!atEdge) {
            sidebarHoverHeld = false;
            return false;
        }
        if (panels.notifications.height > 0)
            sidebarHoverHeld = true;
        return !sidebarHoverHeld;
    }

    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive

    // caelestia-overlay: a panel opens on hover from the screen's edge only, with no button held and no window
    // being dragged (WindowDrag); open, it stays while the pointer is over it
    // (the edge: its last edgePx pixels. Not the last one alone: Caelestia's dots set Hyprland's cursor:hotspot_padding
    // to 1, which keeps the pointer a pixel short of every edge, and no panel opened on hover at all)
    readonly property int edgePx: 3
    function edgeHover(open: bool, atEdge: bool): bool {
        return open || (!pressed && !WindowDrag.dragging && atEdge);
    }
    // ...another screen beyond that side of this one (side by side, or one above the other)
    function sideShared(side: string): bool {
        const s = root.screen;
        // (left and right as the mirror has them)
        if (root.barRight && (side === "left" || side === "right"))
            side = side === "left" ? "right" : "left";
        for (const o of Quickshell.screens) {
            if (o === s)
                continue;
            const alongX = o.x < s.x + s.width && o.x + o.width > s.x;
            const alongY = o.y < s.y + s.height && o.y + o.height > s.y;
            if ((side === "top" && alongX && o.y + o.height === s.y) || (side === "bottom" && alongX && o.y === s.y + s.height)
                    || (side === "right" && alongY && o.x === s.x + s.width) || (side === "left" && alongY && o.x + o.width === s.x))
                return true;
        }
        return false;
    }
    property bool sidebarShortcutActive

    // caelestia-overlay: safe triangle for the bar popouts. Its tip stays where the pointer was when it last
    // wasn't heading for the popout, so the whole path from the button counts, not each tiny step
    property point aimAnchor: Qt.point(-1, -1)
    property real aimY

    function aimSide(ax: real, ay: real, bx: real, by: real, cx: real, cy: real): real {
        return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy);
    }

    function inTriangle(x: real, y: real, ax: real, ay: real, bx: real, by: real, cx: real, cy: real): bool {
        const d1 = aimSide(x, y, ax, ay, bx, by);
        const d2 = aimSide(x, y, bx, by, cx, cy);
        const d3 = aimSide(x, y, cx, cy, ax, ay);
        return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
    }

    function aimPopout(sx: real, sy: real): void {
        // (in the bar's terms: x across it, y along it)
        const x = bu(sx, sy), y = bv(sx, sy);
        aimY = y;
        const a = aimAnchor;
        const w = panels.popoutsWrapper;
        if (popouts.hasCurrent && w.width > 0 && w.height > 0 && a.x >= 0) {
            const px = barTop ? innerY + w.y : barBottom ? height - innerY - w.y - w.height : bar.implicitWidth + vx(w);
            const top = across ? borderThickness + w.x : borderThickness + w.y;
            // Only the part of the popout within a 2:1 slope of the anchor (~63° up or down): with a tall popout,
            // a triangle to its far corners would swallow moves along the bar to the next buttons
            const reach = (px - a.x) * 2;
            const t = Math.max(top, a.y - reach);
            const b = Math.min(top + (across ? w.width : w.height), a.y + reach);
            // Tip 1 px left of the anchor, so a first step straight down/up still counts
            if (t < b && inTriangle(x, y, a.x - 1, a.y, px, t, px, b)) {
                aimTimer.restart(); // heading for the popout: switch only if the pointer stops here
                return;
            }
        }
        aimAnchor = Qt.point(x, y);
        aimTimer.stop();
        bar.checkPopout(y);
    }

    property Timer aimTimer: Timer {
        interval: 300
        onTriggered: {
            root.aimAnchor = Qt.point(root.bu(root.mouseX, root.mouseY), root.bv(root.mouseX, root.mouseY));
            if (root.containsMouse && root.onBar(root.mouseX, root.mouseY))
                root.bar.checkPopout(root.aimY);
        }
    }

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.innerY + panel.y;
        return y >= panelY - config.border.rounding && y <= panelY + panel.height + config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = innerX + vx(panel);
        return x >= panelX - config.border.rounding && x <= panelX + panel.width + config.border.rounding;
    }

    // (the bar's popouts: between the bar and the popout's far side, within its span)
    function inLeftPanel(panel: Item, x: real, y: real): bool {
        if (barTop)
            return y < innerY + panel.y + panel.height && withinPanelWidth(panel, x, y);
        if (barBottom)
            return y > innerY + panel.y && withinPanelWidth(panel, x, y);
        return x < innerX + vx(panel) + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - config.border.minThickness, innerX + vx(panel)) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(config.border.minThickness, topInset + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(config.border.minThickness, bottomInset + panelHeight) - (isCorner ? config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function wheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        const x = mx(event.x);
        if (onBar(x, event.y)) {
            bar.handleWheel(bv(x, event.y), event.angleDelta);
        }
    }

    function press(x: real, y: real, button: int): void {
        dragStart = Qt.point(x, y);
        // caelestia-overlay: a right-click on the bar opens its menu (again, where clicked), any other click closes it
        if (popouts.currentName === "barmenu")
            popouts.hasCurrent = false;
        if (button === Qt.RightButton && onBar(x, y))
            bar.openMenu(bv(x, y));
        // caelestia-overlay: a click anywhere but on the tray closes it
        if (!(onBar(x, y) && bar.trayAt(bv(x, y))))
            bar.closeTray();
    }

    // The pointer out of every window of the shell (Caelestia's onContainsMouseChanged, to false)
    function left(): void {
        sidebarHoverHeld = false; // caelestia-overlay
        // Only hide if not activated by shortcut
        if (!osdShortcutActive) {
            screenState.osd = false;
            root.panels.osd.hovered = false;
        }

        if (!dashboardShortcutActive)
            screenState.dashboard = false;

        if (!utilitiesShortcutActive)
            screenState.utilities = false;

        if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        if (config.bar.showOnHover)
            bar.isHovered = false;

        if (config.sidebar.showOnHover && !sidebarShortcutActive)
            screenState.sidebar = false;
    }

    function move(x: real, y: real): void {
        root.sidebarHoverOpens(root.atSidebarEdge(x, y)); // caelestia-overlay: let go on every path
        mouseX = x;
        mouseY = y;
        if (popouts.isDetached)
            return;

        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y) && root.edgeHover(root.panels.osd.hovered, x >= width - root.edgePx || root.sideShared("right"));
            return;
        }

        // Show bar in non-exclusive mode on hover
        if (!screenState.bar && config.bar.showOnHover && bu(x, y) < bar.clampedWidth)
            bar.isHovered = true;

        // Show/hide bar on drag (across it, away from its edge)
        const dragOut = barTop ? dragY : barBottom ? -dragY : dragX;
        if (pressed && bu(dragStart.x, dragStart.y) < bar.clampedWidth) {
            if (dragOut > config.bar.dragThreshold)
                screenState.bar = true;
            else if (dragOut < -config.bar.dragThreshold)
                screenState.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y) && root.edgeHover(screenState.osd, x >= width - root.edgePx || root.sideShared("right"));

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && !sidebarLeft && dragStart.x > Math.min(width - config.border.minThickness, innerX + vx(panels.sidebar));

            // Show sidebar on hover (top-right corner, bounded by notification panel height)
            if (config.sidebar.showOnHover && !screenState.session) {
                const showSidebarHover = root.atSidebarEdge(x, y);
                if (root.sidebarHoverOpens(showSidebarHover) && !screenState.sidebar && !screenState.dashboard)
                    screenState.sidebar = true;
            }

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > config.session.dragThreshold)
                    screenState.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -config.sidebar.dragThreshold)
                    screenState.sidebar = true;
            } else if (showSidebar && dragX < -config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                screenState.sidebar = true;
            }
        } else {
            const outOfSidebar = sidebarLeft ? x > innerX + panels.sidebar.width * (1 - panels.sidebar.offsetScale) : x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y) && root.edgeHover(screenState.osd, x >= width - root.edgePx || root.sideShared("right"));

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > config.session.dragThreshold)
                    screenState.session = false;
            }

            // Show/hide sidebar on hover
            if (config.sidebar.showOnHover && !pressed) {
                const showSidebarHover = root.atSidebarEdge(x, y);
                if (root.sidebarHoverOpens(showSidebarHover) && !screenState.sidebar && !screenState.dashboard) {
                    screenState.sidebar = true;
                } else {
                    const inSidebarArea = inSidebar(x, y) || inRightPanel(panels.sessionWrapper, x, y);
                    if (inSidebarArea)
                        sidebarShortcutActive = false; // hovered: back to hover control
                    else if (!sidebarShortcutActive)
                        screenState.sidebar = false;
                }
            }

            // Hide sidebar on drag
            if (pressed && !sidebarLeft && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > config.sidebar.dragThreshold)
                screenState.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (barBottom) {
            // (a bottom bar: not from the bottom edge, the bar's there)
        } else if (config.launcher.showOnHover) {
            if (!screenState.launcher && inBottomPanel(panels.launcher, x, y) && root.edgeHover(false, y >= height - root.edgePx || root.sideShared("bottom")))
                screenState.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -config.launcher.dragThreshold)
                screenState.launcher = true;
            else if (dragY > config.launcher.dragThreshold)
                screenState.launcher = false;
        }

        // Show dashboard on hover
        const showDashboard = config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y) && root.edgeHover(screenState.dashboard, !barTop && (y < root.edgePx || root.sideShared("top"))) && (screenState.dashboard || !screenState.sidebar && !withinPanelWidth(panels.sidebar, x, y)); // caelestia-overlay: not over the sidebar's span

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            screenState.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (pressed && !barTop && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > config.dashboard.dragThreshold)
                screenState.dashboard = true;
            else if (dragY < -config.dashboard.dragThreshold)
                screenState.dashboard = false;
        }

        // Show utilities on hover
        const showUtilities = utilitiesTop ? inTopPanel(panels.utilities, x, y) && root.edgeHover(screenState.utilities, y < root.edgePx || root.sideShared("top")) : inBottomPanel(panels.utilities, x, y, true) && root.edgeHover(screenState.utilities, y >= height - root.edgePx || root.sideShared("bottom"));

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            screenState.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Show popouts on hover
        if (onBar(x, y) && !WindowDrag.dragging) {
            root.aimPopout(x, y);
        } else if ((!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    // Monitor individual visibility changes
    property Connections stateChanges: Connections {
        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.screenState.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.sidebarShortcutActive = false;
                if (!root.inSidebar(root.mouseX, root.mouseY))
                    root.screenState.sidebar = false;
                if (!root.inUtilities(root.mouseX, root.mouseY))
                    root.screenState.utilities = false;

                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.screenState.dashboard = false;
                }
                if (!inOsdArea) {
                    root.screenState.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.screenState.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.screenState.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onSidebarChanged() {
            // Not when the hover trigger (the top edge over it) opened it: it's still above the screen then
            const border = root.config.border;
            const band = Math.max(border.minThickness, border.thickness) + border.rounding;
            const inTrigger = (root.sidebarLeft ? root.mouseY > root.height - band : root.mouseY < band)
                && root.withinPanelWidth(root.panels.sidebar, root.mouseX, root.mouseY);
            if (root.screenState.sidebar)
                root.sidebarShortcutActive = !inTrigger && !root.inSidebar(root.mouseX, root.mouseY);
            else
                root.sidebarShortcutActive = false;
        }

        function onUtilitiesChanged() {
            if (root.screenState.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inUtilities(root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.screenState
    }

    // caelestia-overlay: a notification pop-up showing under a pointer resting on the sidebar's hover edge holds it
    property Connections notificationChanges: Connections {
        function onHeightChanged() {
            if (root.containsMouse && root.panels.notifications.height > 0)
                root.sidebarHoverOpens(root.atSidebarEdge(root.mouseX, root.mouseY));
        }

        target: root.panels.notifications
    }
}
