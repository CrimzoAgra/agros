pragma ComponentBehavior: Bound

// caelestia-overlay (split_windows): one of a screen's four shell windows, the left one (bar, its popouts), the right
// one (sidebar, session, OSD, notifications, utilities, toasts), the top one (dashboard) or the bottom one (launcher).
// Between them they cover the border, each its stretch of it, so every pixel of the shell is drawn by one window only.
// Caelestia drew all of it as one full-screen window: a panel sliding in had the whole 2560x1440 redrawn, by the shell
// and by Hyprland (with the blur under it), every frame. Here only the window of what moves is.
// Inside, everything is placed in screen coordinates (space: a full-screen item, shifted by where this window is), so
// the panels, their blob backgrounds, the border and the pointer's tests are Caelestia's own, unchanged

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar as Bar

StyledWindow {
    id: root

    // left, right, top or bottom (with the bar on the right, "left" is the bar's window, on the right: Drawers.qml)
    required property string part
    // The bar on the right (Drawers.qml's barRight): the border's side and the inner area mirrored
    property bool barRight
    // This window on the screen (logical pixels): room for its panels, kept (a window resized as a panel opened or
    // closed showed its old picture at the new size for a frame, a flicker)
    required property rect area
    // The part of the screen whose border (and shadow, and pointer) is this window's now, in screen coordinates: the
    // four windows' parts cover the border between them, each pixel once, and change as panels open and close. The
    // windows overlap; each draws only its own part (shown: a part growing is drawn at once, one shrinking a moment
    // later, so as the parts move the border is drawn twice for a moment rather than missing)
    required property rect own
    property rect shown: own
    required property Controller controller
    // The screen's bar (the left window's), for the border's left side and the panels' place
    property Bar.BarWrapper bar
    // Whether the screen's shell holds the pointer to its windows (HyprlandFocusGrab, Drawers.qml)
    property bool grabActive
    // Over a fullscreen window, whether something of this window shows there besides the whole shell (the right
    // window's notifications, volume popup and toasts)
    property bool showsOverFullscreen
    // Whether this window takes the keyboard (the launcher's, the session menu's)
    property bool wantsKeyboard
    // The input region besides this window's stretch of the border: Regions of panels, in screen coordinates (R)
    default property alias content: interactions.data
    property alias regions: panelRegions.regions
    property alias hiddenRegions: hiddenRegion.regions
    property alias blobs: blobSpace.data
    readonly property alias blobGroup: blobGroup
    readonly property alias interactions: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)
    // The screen's, from Drawers.qml (each window looking its own up had its size depend on itself: a binding loop)
    required property HyprlandMonitor monitor
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    readonly property bool shellHidden: hasFullscreen && !screenState.launcher
    property real fsTransitionProg: shellHidden ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: shellHidden ? 0 : contentItem.Config.border.thickness
    readonly property real barWidth: bar?.implicitWidth ?? 0
    // Where the screen's inner area (less the bar and border) starts: after the bar, or after the left border
    readonly property real innerLeft: barRight ? borderThickness : barWidth

    property color surfaceColour: Colours.tPalette.m3surface

    // How far in from the border the input reaches on an empty workspace, for dragging panels out (Caelestia's)
    readonly property int dragMaskPadding: {
        if (grabActive || (controller.popouts?.isDetached ?? false))
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    name: "drawers"
    anchors.top: true
    anchors.left: true
    margins.left: Math.round(area.x)
    margins.top: Math.round(area.y)
    implicitWidth: Math.max(1, Math.round(area.width))
    implicitHeight: Math.max(1, Math.round(area.height))
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // Above a fullscreen window only while something of it shows there (the whole shell: the Super menu open, its
    // opening and closing; or what showsOverFullscreen says), else under it: an overlay above a fullscreen game, even an
    // empty one, has Hyprland redraw the whole screen every frame instead of showing the game's frames alone
    WlrLayershell.layer: ((hasFullscreen ? fsTransitionProg < 1 || showsOverFullscreen : fsTransitionProg > 0) && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: shellHidden ? hiddenRegion : inputRegion

    Behavior on fsTransitionProg {
        Anim {}
    }

    onOwnChanged: {
        const x = Math.min(shown.x, own.x), y = Math.min(shown.y, own.y);
        shown = Qt.rect(x, y, Math.max(shown.x + shown.width, own.x + own.width) - x, Math.max(shown.y + shown.height, own.y + own.height) - y);
        shrink.restart();
    }

    Timer {
        id: shrink

        interval: 60
        onTriggered: root.shown = root.own
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    // Fullscreen: only what shows over the window takes the pointer (hiddenRegions)
    Region {
        id: hiddenRegion
    }

    // This window's part of the border (its part of the screen minus the inner area, as Caelestia's Regions.qml), and
    // its panels (regions)
    Region {
        id: inputRegion

        x: root.own.x - root.area.x
        y: root.own.y - root.area.y
        width: root.own.width
        height: root.own.height

        Region {
            x: (root.barRight ? root.contentItem.Config.border.clampedThickness : root.bar.clampedWidth) + root.dragMaskPadding - root.area.x
            y: root.contentItem.Config.border.clampedThickness + root.dragMaskPadding - root.area.y
            width: root.screen.width - root.bar.clampedWidth - root.contentItem.Config.border.clampedThickness - root.dragMaskPadding * 2
            height: root.screen.height - root.contentItem.Config.border.clampedThickness * 2 - root.dragMaskPadding * 2
            intersection: Intersection.Subtract
        }

        Region {
            id: panelRegions
        }
    }

    // The shell's shapes (border and panels' backgrounds, merged into one) with their shadow, shown in this window's part
    // only: drawn a little past it (pad), so the shadow along the border, cut where the next window's part starts, is
    // the same each side
    Item {
        id: shownPart

        x: root.shown.x - root.area.x
        y: root.shown.y - root.area.y
        width: root.shown.width
        height: root.shown.height
        clip: true

        Item {
            readonly property real pad: 48

            x: -pad - shownPart.x
            y: -pad - shownPart.y
            width: root.width + pad * 2
            height: root.height + pad * 2
            opacity: root.surfaceColour.a
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
            }

            Item {
                id: blobSpace

                x: parent.pad - root.area.x
                y: parent.pad - root.area.y
                width: root.screen.width
                height: root.screen.height

                BlobGroup {
                    id: blobGroup

                    color: root.surfaceColour
                    smoothing: root.contentItem.Config.border.smoothing
                }

                BlobInvertedRect {
                    anchors.fill: parent
                    anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
                    group: blobGroup
                    radius: root.borderRounding
                    borderLeft: (root.barRight ? root.borderThickness : root.barWidth) - anchors.margins - root.sdfBorderOffset
                    borderRight: (root.barRight ? root.barWidth : root.borderThickness) - anchors.margins - root.sdfBorderOffset
                    borderTop: root.borderThickness - anchors.margins - root.sdfBorderOffset
                    borderBottom: root.borderThickness - anchors.margins - root.sdfBorderOffset
                }
            }
        }
    }

    // The pointer over this window, told to the screen's controller in screen coordinates; the panels and the bar
    // inside it, as in Caelestia's window
    Interactions {
        id: interactions

        controller: root.controller
        x: -root.area.x
        y: -root.area.y
        width: root.screen.width
        height: root.screen.height
    }
}
