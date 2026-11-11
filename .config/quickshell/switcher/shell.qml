// Super+Tab workspace switcher in Caelestia's style: a row of live previews of the workspaces that have windows,
// in workspace order. Tab cycles on from the current one (wrapping round).
//   Super+Tab / Super+Shift+Tab  open it on the next / previous one, or move along; releasing Super goes there
//   Escape cancels; clicking a preview goes there, or clicking a window in it brings that window up, as in Alt+Tab (the
//   mouse over one only highlights it, and outlines the window under it: Tab, the arrow keys or a click pick)
// Alt+Tab opens the same panel for the windows of the current workspace instead (minimised ones too, which come
// back when picked), most recently used first, so a quick Alt+Tab goes to the previous window; releasing Alt picks
// The keys are bound in ~/.config/caelestia/user/keys.lua to these global shortcuts: Hyprland hands them over in the
// order they happen, so a quick Super+Tab (Super let go before this has even opened) still switches. Workspaces are columns as in
// the synced Super+N: workspace N is N on every screen, and switching goes through dots.goto_workspace(N) there.
// The previews show the screen the switcher opens on; the icons under them, the windows on every screen.
// Separate from Caelestia, so Caelestia updates don't touch it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // The wallpaper Caelestia shows (the file it names in path.txt, followed as it changes: a URL of the fixed link to
    // it, "current", kept the old picture in the image cache after a change); a file URL, each part encoded ("#", "%")
    FileView {
        path: `${root.home}/.local/state/caelestia/wallpaper/path.txt`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaperFile = text().trim()
    }
    property string wallpaperFile
    readonly property string wallpaper: {
        const p = wallpaperFile || `${home}/.local/state/caelestia/wallpaper/current`;
        return `file://${p.split("/").map(encodeURIComponent).join("/")}`;
    }

    // Caelestia's colours: ../common/Scheme.qml (not an import: Quickshell blocks those from outside this folder)
    Loader {
        id: scheme
        source: `file://${Quickshell.shellPath("../common/Scheme.qml")}`
    }
    function c(name: string): color {
        return scheme.item?.c(name) ?? "transparent";
    }

    property bool open: false
    property string mode: "workspaces" // or "windows" (Alt+Tab)
    property var cards: [] // workspace columns (1-10), or windows, in the order shown
    property int selected: 0
    property var wasActive: null // Alt+Tab: the window active when it opened (its first card)

    readonly property HyprlandMonitor monitor: Hyprland.focusedMonitor
    readonly property int current: column(activeId())

    // Workspaces as Hyprland last reported them (the IPC data, refreshed before each use), not Quickshell's objects: a
    // window that opened on a workspace Quickshell wasn't tracking yet (this starts at login, before workspace 1 exists)
    // has none, and Alt+Tab then found no windows at all until the switcher was restarted
    function wsOf(t: var): var {
        return t.lastIpcObject?.workspace ?? t.workspace ?? null;
    }
    // The live value (it follows Super+N; the IPC copy only updates when asked), that copy only when it's missing (at login)
    function activeId(): int {
        return monitor?.activeWorkspace?.id ?? monitor?.lastIpcObject?.activeWorkspace?.id ?? 1;
    }

    // Workspace id -> its column: 1-10 on the 1st screen, 11-20 on the 2nd... (0 for special workspaces). With one
    // screen nothing is folded: 11 and up are workspaces of their own there (dots.goto_workspace does the same)
    function column(id: int): int {
        return id > 0 ? (Hyprland.monitors.values.length >= 2 ? (id - 1) % 10 + 1 : id) : 0;
    }

    // A window's column, minimised ones included (they wait on special:minimised-N for workspace N: user/windows.lua)
    function columnOf(t: var): int {
        const min = wsOf(t)?.name?.match(/^special:minimised-(\d+)$/);
        return min ? column(parseInt(min[1])) : column(wsOf(t)?.id ?? 0);
    }

    function windowsIn(col: int): var {
        return Hyprland.toplevels.values.filter(t => wsOf(t) && columnOf(t) === col && t.lastIpcObject?.mapped);
    }

    // The current workspace's windows (and its minimised ones, on special:minimised-N: user/windows.lua), last used first.
    // Not X11 apps' menus (tagged xwl_popup in user/apps.lua)
    function workspaceWindows(): var {
        const ws = activeId();
        return Hyprland.toplevels.values.filter(t => {
            const ipc = t.lastIpcObject;
            return ipc?.mapped && (wsOf(t)?.id === ws || wsOf(t)?.name === `special:minimised-${ws}`) && !(ipc.tags ?? []).some(g => g.startsWith("xwl_popup"));
        }).sort((a, b) => recency(a) - recency(b));
    }

    // How recently a window was focused, 0 the latest. Never focused (Hyprland's -1: a store launcher minimised as it
    // opened, a window opened in the background) or unknown: last, not ahead of the active window (a quick Alt+Tab
    // then went to the window you were already on)
    function recency(t: var): int {
        const id = t.lastIpcObject?.focusHistoryID ?? -1;
        return id >= 0 ? id : 1e6;
    }

    function stepWindows(dir: int): void {
        if (open && mode !== "windows")
            return;
        if (!open) {
            Hyprland.refreshToplevels();
            Hyprland.refreshMonitors();
            const list = workspaceWindows();
            if (!list.length)
                return;
            cards = list;
            wasActive = list[0];
            selected = 0;
            mode = "windows";
            open = true;
        }
        selected = (selected + dir + cards.length) % cards.length;
    }

    function step(dir: int): void {
        if (open && mode !== "workspaces")
            return;
        if (!open) {
            mode = "workspaces";
            Hyprland.refreshToplevels();
            const used = new Set(Hyprland.toplevels.values.map(t => columnOf(t)).filter(c => c > 0));
            used.add(current);
            cards = [...used].sort((a, b) => a - b);
            selected = cards.indexOf(current);
            open = true;
        }
        selected = (selected + dir + cards.length) % cards.length;
    }

    // Arrow keys: along the cards, in either mode
    function move(dir: int): void {
        if (open)
            selected = (selected + dir + cards.length) % cards.length;
    }

    // A window closing while the window cards are up: its card goes (it would freeze, and picking it do nothing)
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged(): void {
            if (!root.open || root.mode !== "windows")
                return;
            const picked = root.cards[root.selected];
            root.cards = root.cards.filter(c => Hyprland.toplevels.values.includes(c));
            if (!root.cards.length)
                root.open = false;
            else // the same window stays picked (its index moves when one before it goes)
                root.selected = root.cards.includes(picked) ? root.cards.indexOf(picked) : Math.min(root.selected, root.cards.length - 1);
        }
    }

    function commit(): void {
        if (!open)
            return;
        open = false;
        if (mode === "windows") {
            const w = cards[selected];
            // dots.focus_window (user/windows.lua) also brings a floating window to the front and a minimised one back;
            // true: it's Alt+Tab, which minimises a fullscreen window left behind
            // (by the window, not card 0: the active one closing while Alt is held moves the picked one to card 0)
            if (w && (w !== wasActive || (wsOf(w)?.id ?? 0) < 1))
                Quickshell.execDetached(["hyprctl", "eval", `dots.focus_window("0x${w.address}", true)`]);
            return;
        }
        const col = cards[selected];
        if (col && col !== current)
            Quickshell.execDetached(["hyprctl", "eval", `dots.goto_workspace(${col})`]);
    }

    // A window's icon: the dock's and bar's lookup, ../common/WindowApps.qml
    Loader {
        id: windowApps
        source: `file://${Quickshell.shellPath("../common/WindowApps.qml")}`
    }
    function iconFor(cls: string): string {
        return Quickshell.iconPath(windowApps.item?.iconName(cls) ?? "", "application-x-executable");
    }

    GlobalShortcut {
        appid: "switcher"
        name: "next"
        onPressed: root.step(1)
    }

    GlobalShortcut {
        appid: "switcher"
        name: "prev"
        onPressed: root.step(-1)
    }

    GlobalShortcut {
        appid: "switcher"
        name: "windows-next"
        onPressed: root.stepWindows(1)
    }

    GlobalShortcut {
        appid: "switcher"
        name: "windows-prev"
        onPressed: root.stepWindows(-1)
    }

    GlobalShortcut {
        appid: "switcher"
        name: "commit"
        // Sent when Super or Alt is let go (user/keys.lua's key hook, as a global shortcut): handled as a press or a release
        onPressed: root.commit()
        onReleased: root.commit()
    }

    // The same from scripts: qs -c switcher ipc call switcher next|prev|commit|cancel
    IpcHandler {
        target: "switcher"

        function next(): void {
            root.step(1);
        }
        function prev(): void {
            root.step(-1);
        }
        function commit(): void {
            root.commit();
        }
        function cancel(): void {
            root.open = false;
        }
    }

    // Keep window positions fresh (same events Caelestia listens to)
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;
            if (["openwindow", "closewindow", "movewindow", "activewindow", "windowtitle", "changefloatingmode", "fullscreen"].includes(n))
                Hyprland.refreshToplevels();
            if (["workspace", "focusedmon", "moveworkspace", "openwindow", "closewindow", "movewindow"].includes(n))
                Hyprland.refreshWorkspaces();
        }
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
    }

    PanelWindow {
        id: win

        // (width and height of its mode, swapped on a screen turned sideways)
        readonly property bool turned: (root.monitor?.lastIpcObject?.transform ?? 0) % 2 === 1
        readonly property real monW: root.monitor ? (turned ? root.monitor.height : root.monitor.width) / root.monitor.scale : 1920
        readonly property real monH: root.monitor ? (turned ? root.monitor.width : root.monitor.height) / root.monitor.scale : 1080
        readonly property int spacing: 16
        // Previews as big as fit on the screen, at most 300 px wide
        readonly property real cardW: Math.min(300, (monW * 0.9 - 48 - (root.cards.length - 1) * spacing) / Math.max(1, root.cards.length))
        readonly property real scaleF: cardW / monW

        screen: Quickshell.screens.find(s => s.name === root.monitor?.name) ?? Quickshell.screens[0]
        visible: root.open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "workspace-switcher"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        // Click outside the panel: cancel
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Item {
            focus: true
            // Releasing Super (workspaces) or Alt (windows) picks (user/keys.lua's key hook does too; whichever comes first)
            Keys.onReleased: event => {
                if (root.mode === "windows" ? event.key === Qt.Key_Alt : (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta))
                    root.commit();
            }
            Keys.onEscapePressed: root.open = false
            Keys.onReturnPressed: root.commit()
            Keys.onLeftPressed: root.move(-1)
            Keys.onRightPressed: root.move(1)
        }

        Rectangle {
            id: panel

            anchors.centerIn: parent
            implicitWidth: row.implicitWidth + 48
            implicitHeight: row.implicitHeight + 48
            radius: 28
            color: Qt.alpha(root.c("surfaceContainer"), 0.92)
            border.color: Qt.alpha(root.c("outlineVariant"), 0.6)
            border.width: 1

            // Swallow clicks on the panel itself (not a cancel)
            MouseArea {
                anchors.fill: parent
            }

            RowLayout {
                id: row

                anchors.centerIn: parent
                spacing: win.spacing

                Repeater {
                    model: root.open && root.mode === "workspaces" ? root.cards : []

                    ColumnLayout {
                        id: card

                        required property int modelData
                        required property int index
                        readonly property bool isSelected: index === root.selected
                        readonly property var wins: root.windowsIn(modelData)
                        // The previewed workspace: this column on the screen the switcher is on (minimised windows
                        // aren't on it: they only show as icons)
                        readonly property var shown: wins.filter(t => root.wsOf(t)?.id > 0 && (t.lastIpcObject?.monitor ?? t.workspace?.monitor?.id) === root.monitor?.id)
                        // Floating ones last, as they're drawn (on top)
                        readonly property var stacked: shown.slice().sort((a, b) => (a.lastIpcObject.floating ? 1 : 0) - (b.lastIpcObject.floating ? 1 : 0))
                        // The window under the pointer in the preview (clicked: that window, as in Alt+Tab)
                        property var hovered: null

                        // The window at x, y of the preview's frame (its 4 px margin in): the topmost there, or null
                        function windowAt(x: real, y: real): var {
                            const px = (x - 4) / win.scaleF + (root.monitor?.x ?? 0), py = (y - 4) / win.scaleF + (root.monitor?.y ?? 0);
                            for (let i = stacked.length - 1; i >= 0; i--) {
                                const ipc = stacked[i].lastIpcObject;
                                if (px >= ipc.at[0] && px < ipc.at[0] + ipc.size[0] && py >= ipc.at[1] && py < ipc.at[1] + ipc.size[1])
                                    return stacked[i];
                            }
                            return null;
                        }

                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: win.cardW + 8
                            Layout.preferredHeight: win.monH * win.scaleF + 8
                            radius: 18
                            color: "transparent"
                            // Picked: the full colour; under the mouse only: a faint one
                            border.color: card.isSelected ? root.c("primary") : cardMouse.containsMouse ? Qt.alpha(root.c("primary"), 0.35) : "transparent"
                            border.width: 3

                            Behavior on border.color {
                                ColorAnimation { duration: 40 }
                            }

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 14
                                color: root.c("surfaceContainerHighest")

                                Image {
                                    property string failedFor

                                    anchors.fill: parent
                                    // A video wallpaper (Caelestia's coming ones) isn't a picture: its still that
                                    // Caelestia keeps instead (for that one only: a new wallpaper's tried first)
                                    source: failedFor === root.wallpaper ? `file://${root.home}/.local/state/caelestia/wallpaper/thumbnail.jpg` : root.wallpaper
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 400
                                    asynchronous: true
                                    cache: true
                                    onStatusChanged: if (status === Image.Error) failedFor = root.wallpaper
                                }

                                // Floating windows last, so they're drawn on top like on screen. Kept per window as the
                                // list changes (each title change refreshes it): rebuilding every live picture at once
                                // is what crashed Caelestia's shell
                                Repeater {
                                    model: ScriptModel {
                                        values: card.stacked
                                        objectProp: "address"
                                    }

                                    ScreencopyView {
                                        required property var modelData
                                        readonly property var ipc: modelData.lastIpcObject

                                        x: (ipc.at[0] - (root.monitor?.x ?? 0)) * win.scaleF
                                        y: (ipc.at[1] - (root.monitor?.y ?? 0)) * win.scaleF
                                        width: ipc.size[0] * win.scaleF
                                        height: ipc.size[1] * win.scaleF
                                        captureSource: modelData.wayland
                                        live: root.open
                                    }
                                }

                                // The window under the pointer: outlined over the others (one behind shows whole)
                                Rectangle {
                                    readonly property var ipc: card.hovered?.lastIpcObject
                                    visible: !!ipc
                                    x: ipc ? (ipc.at[0] - (root.monitor?.x ?? 0)) * win.scaleF : 0
                                    y: ipc ? (ipc.at[1] - (root.monitor?.y ?? 0)) * win.scaleF : 0
                                    width: ipc ? ipc.size[0] * win.scaleF : 0
                                    height: ipc ? ipc.size[1] * win.scaleF : 0
                                    color: "transparent"
                                    radius: 4
                                    border.width: 2
                                    border.color: root.c("primary")
                                }
                            }

                            MouseArea {
                                id: cardMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: mouse => card.hovered = card.windowAt(mouse.x, mouse.y)
                                onExited: card.hovered = null
                                // On a window: that window (Alt+Tab's click, dots.focus_window); elsewhere: the workspace
                                onClicked: mouse => {
                                    const w = card.windowAt(mouse.x, mouse.y);
                                    if (!w) {
                                        root.selected = card.index;
                                        root.commit();
                                        return;
                                    }
                                    root.open = false;
                                    Quickshell.execDetached(["hyprctl", "eval", `dots.focus_window("0x${w.address}", true)`]);
                                }
                            }
                        }

                        // Number and app icons, grouped in the middle under the preview
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6

                            Rectangle {
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: 13
                                color: card.isSelected ? root.c("primary") : root.c("surfaceContainerHighest")

                                Text {
                                    anchors.centerIn: parent
                                    text: card.modelData
                                    font.family: "Rubik"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: card.isSelected ? root.c("onPrimary") : root.c("onSurface")
                                }
                            }

                            Repeater {
                                // One icon per app, at most six
                                model: [...new Set(card.wins.map(t => t.lastIpcObject.class))].slice(0, 6)

                                IconImage {
                                    required property string modelData

                                    anchors.verticalCenter: parent?.verticalCenter
                                    implicitSize: 22
                                    // Looked up again once the app list has loaded (it loads in the background)
                                    source: (DesktopEntries.applications.values.length, root.iconFor(modelData))
                                }
                            }
                        }
                    }
                }

                // Alt+Tab: one card per window, in the same frame as a workspace's
                Repeater {
                    // (kept per window as windows close: see the toplevels Connections above)
                    model: ScriptModel {
                        values: root.open && root.mode === "windows" ? root.cards : []
                        objectProp: "address"
                    }

                    ColumnLayout {
                        id: wcard

                        required property var modelData
                        required property int index
                        readonly property bool isSelected: index === root.selected
                        readonly property var ipc: modelData?.lastIpcObject ?? ({})
                        readonly property bool minimised: (root.wsOf(modelData)?.id ?? 0) < 1
                        // The frame takes the window's shape, within the space a workspace card has
                        readonly property real aspect: Math.max(1, ipc.size?.[0] ?? 1) / Math.max(1, ipc.size?.[1] ?? 1)
                        readonly property real frameW: Math.min(win.cardW, win.monH * win.scaleF * aspect)
                        readonly property real frameH: frameW / aspect

                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: wcard.frameW + 8
                            Layout.preferredHeight: wcard.frameH + 8
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            radius: 18
                            color: "transparent"
                            // Picked: the full colour; under the mouse only: a faint one
                            border.color: wcard.isSelected ? root.c("primary") : wcardMouse.containsMouse ? Qt.alpha(root.c("primary"), 0.35) : "transparent"
                            border.width: 3

                            Behavior on border.color {
                                ColorAnimation { duration: 40 }
                            }

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 14
                                color: root.c("surfaceContainerHighest")

                                // Under the preview: what shows while a minimised window (not drawn) has none
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 48
                                    source: (DesktopEntries.applications.values.length, root.iconFor(wcard.ipc.class))
                                }

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: wcard.modelData.wayland
                                    live: root.open
                                    opacity: wcard.minimised ? 0.5 : 1
                                }
                            }

                            MouseArea {
                                id: wcardMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selected = wcard.index;
                                    root.commit();
                                }
                            }
                        }

                        // App icon and title, in the middle under the preview
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: Math.max(wcard.frameW, 120)
                            spacing: 6

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 22
                                source: (DesktopEntries.applications.values.length, root.iconFor(wcard.ipc.class))
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.max(wcard.frameW, 120) - 28)
                                text: wcard.ipc.title || wcard.ipc.class
                                elide: Text.ElideRight
                                font.family: "Rubik"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: wcard.isSelected ? root.c("primary") : root.c("onSurface")
                            }
                        }
                    }
                }
            }
        }
    }
}
