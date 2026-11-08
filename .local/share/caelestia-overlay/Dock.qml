pragma ComponentBehavior: Bound

// caelestia-overlay: dock (pinned apps + open windows on this monitor's workspace).
// Pins: ~/.config/quickshell/sidedock/pins.json (separate from the launcher favourites).
// Hover an icon for its popout; left click = focus/open, middle click = close.
// Drag an icon to reorder the pinned apps (dropping an open window among them pins it).

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.launcher.services

// Quickshell's ClippingRectangle directly, not Caelestia's StyledClippingRect wrapper (gone in later Caelestia versions)
ClippingRectangle {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property alias flick: flick
    property var pins: []
    // The drags' numbers for caelestia-pin --order: this dock's run (only told apart, never compared) and a count
    readonly property string orderRun: `${Date.now()}-${Math.floor(Math.random() * 1e6)}`
    property int orderSeq: 0
    property var popouts: null

    // Drag to reorder: index (in items) of the dragged cell, where it would land, cursor y in the column
    property int dragFrom: -1
    property int dragTo: -1
    property real dragY
    readonly property bool dragging: dragFrom >= 0
    readonly property int firstPinned: items.findIndex(i => i.pinned)
    // Set by the first focus change Hyprland reports (after that, an empty workspace means no window has focus)
    property bool focusKnown: false
    // Window addresses, the last focused first: which of an app's windows its icon brings up
    property var recent: []

    Connections {
        target: Hyprland
        function onActiveToplevelChanged(): void {
            root.focusKnown = true;
            const a = Hyprland.activeToplevel?.address;
            if (a)
                root.recent = [a, ...root.recent.filter(r => r !== a && Hypr.toplevels.values.some(t => t.address === r))];
        }
    }

    // Minimised windows too: they wait on special:minimised-N for workspace N (user/windows.lua; clicking one brings it back).
    // Only windows Hyprland reports as mapped: one that opens and closes at once can leave Quickshell an entry with no
    // details that never goes away (a gear icon nothing could close)
    readonly property var wins: Hypr.toplevels.values.filter(t => t.lastIpcObject?.mapped && monitor?.activeWorkspace && (t.workspace?.id === monitor.activeWorkspace.id || t.workspace?.name === `special:minimised-${monitor.activeWorkspace.id}`) && !Hypr.isToplevelIgnored(t, ["xwl_popup"]))  // not menus/popups of X11 apps (e.g. Steam's top menus)

    // One icon per app: the apps with windows open that aren't pinned first, then the pinned apps. wins: the app's
    // windows here (in the order they opened); win: the one its icon brings up (the focused one, else the last focused)
    readonly property var items: {
        if (!DesktopEntries.applications.values.length)
            return [];
        const groups = new Map();
        for (const t of wins) {
            const k = keyFor(t.lastIpcObject.class);
            if (!groups.has(k))
                groups.set(k, []);
            groups.get(k).push(t);
        }
        const rank = t => {
            const i = recent.indexOf(t.address);
            // (never focused, Hyprland's -1: after every focused one)
            const h = t.lastIpcObject.focusHistoryID ?? -1;
            return i >= 0 ? i : 1000 + (h >= 0 ? h : 1e6);
        };
        const pick = ws => ws.find(t => t.activated) ?? [...ws].sort((a, b) => rank(a) - rank(b))[0] ?? null;
        const used = new Set();
        const pinned = [];
        for (const p of pins) {
            const entry = entryFor(p);
            if (!entry || used.has(entry.id))
                continue;
            used.add(entry.id);
            const ws = groups.get(entry.id) ?? [];
            pinned.push({ uid: "pin:" + entry.id, key: entry.id, entry, wins: ws, win: pick(ws), pinned: true });
        }
        const out = [...groups].filter(([k]) => !used.has(k)).map(([k, ws]) => {
            const entry = entryFor(ws[0].lastIpcObject.class);
            return { uid: "app:" + k, key: entry?.id ?? k, entry, wins: ws, win: pick(ws), pinned: false };
        });
        if (out.length && pinned.length)
            out.push({ uid: "sep", sep: true });
        return out.concat(pinned);
    }

    // A Steam game with no shortcut: its own icon (steam_icon_<id>: game-focus makes it from Steam's cache), else Steam's
    function steamIcon(cls: string): string {
        const game = cls.match(/^steam_app_(\d+)$/);
        if (!game)
            return "";
        return Quickshell.iconPath(`steam_icon_${game[1]}`, true) ? `steam_icon_${game[1]}` : "steam";
    }

    function entryFor(id: string): DesktopEntry {
        if (!id)
            return null; // a window with no class: the lookup would find an unrelated app
        // A Steam game (steam_app_<id>): the shortcut Steam made for it (its name, icon steam_icon_<id>), as the switchers
        // show it; the name lookup found Steam itself
        const game = id.match(/^steam_app_(\d+)$/);
        if (game)
            return DesktopEntries.applications.values.find(e => e.icon === `steam_icon_${game[1]}`) ?? null;
        return DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
    }

    function keyFor(id: string): string {
        return entryFor(id)?.id ?? id;
    }

    // The app cell under a y position (in this item's coordinates), or null
    function cellAt(y: real): Item {
        const c = column.childAt(column.width / 2, mapToItem(column, 0, y).y);
        return c && !c.modelData?.sep ? c : null;
    }

    // Lowest index a dragged item can land on (only the pinned group can be reordered)
    function minDropIndex(): int {
        if (firstPinned < 0)
            return items.length;
        return dragFrom < firstPinned ? firstPinned - 1 : firstPinned;
    }

    function updateDrag(y: real): void {
        dragY = y;
        let to = dragFrom;
        for (let i = 0; i < cells.count; i++) {
            const c = cells.itemAt(i);
            if (c && y >= c.y && y < c.y + c.height + column.spacing)
                to = i;
        }
        if (y >= column.implicitHeight)
            to = items.length - 1;
        dragTo = to < minDropIndex() ? dragFrom : to;

        // Scroll when dragging near the top or bottom edge
        const vy = y - flick.contentY;
        if (vy < 20)
            flick.contentY = Math.max(0, flick.contentY - 6);
        else if (vy > flick.height - 20)
            flick.contentY = Math.min(flick.contentHeight - flick.height, flick.contentY + 6);
    }

    function endDrag(): void {
        const from = dragFrom, to = dragTo;
        dragFrom = dragTo = -1;
        if (from < 0 || to === from || to < 0)
            return;

        const moved = items[from];
        // No launcher entry: a pin of it wouldn't show (nor could be unpinned from the dock)
        if (!moved?.entry && !moved?.pinned)
            return;
        const order = items.filter(i => i.pinned && i !== moved).map(i => i.key);
        const at = Math.max(0, Math.min(order.length, to - firstPinned + (from < firstPinned ? 1 : 0)));
        order.splice(at, 0, moved.key);
        // Keep pins whose app isn't installed right now
        const next = order.concat(pins.filter(p => !order.includes(p) && !order.includes(keyFor(p))));
        // Written by caelestia-pin, under the lock its pin clicks take, merged with a pin landing meanwhile: the order
        // (by entry id, as the dock knows them) and each pin it started from with its entry id, so a pin stored by
        // another name ("Spotify", com.spotify.Client) is matched. Numbered (this dock's run, then its drags): an older
        // drag finishing after a newer one doesn't undo it
        const keys = {};
        for (const p of pins)
            keys[p] = keyFor(p);
        orderSeq++;
        pins = next;
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-pin`, "dock", "--order",
            JSON.stringify({ order: next, keys }), `${orderRun}:${orderSeq}`]);
    }

    // How far a cell moves aside to make room for the dragged one
    function dragShift(i: int): real {
        if (!dragging || i === dragFrom || dragTo === dragFrom)
            return 0;
        const step = (cells.itemAt(dragFrom)?.height ?? 0) + column.spacing;
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo)
            return -step;
        if (dragFrom > dragTo && i >= dragTo && i < dragFrom)
            return step;
        return 0;
    }

    function togglePin(key: string): void {
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-pin`, "dock", key]);
    }

    // Not named focus: that's every item's focus property, which a function of that name doesn't reliably replace
    function focusWindow(win: HyprlandToplevel): void {
        // dots.focus_window (~/.config/caelestia/user/windows.lua) also brings a floating window to the front. Lua
        // commands only, here and in the overlay's other files: this config is Lua, and Caelestia drops Hypr.usingLua
        Quickshell.execDetached(["hyprctl", "eval", `dots.focus_window("0x${win.address}")`]);
    }

    // An app's icon clicked: its window to the front; one of its windows already focused: the next one
    function bringUp(d: var): void {
        const at = d.wins.findIndex(t => t.activated);
        if (at >= 0 && d.wins.length > 1)
            focusWindow(d.wins[(at + 1) % d.wins.length]);
        else
            focusWindow(d.win);
    }

    // Close windows a moment after their previews let go of them: a preview still capturing a closing window broke the
    // shell's connection to Hyprland, which dropped it (bar and all). The dock does it, as the popout closes meanwhile
    // Previews of these let go now and come back after a while if the windows stay (Force quit: the process may not die)
    function forgetSoon(list: var): void {
        closing = [...closing, ...list.map(w => w.address)];
        forgetTimer.restart();
    }

    function closeSoon(list: var): void {
        closing = [...closing, ...list.map(w => w.address)];
        toClose = [...toClose, ...list.map(w => w.address)];
        forgetTimer.stop(); // an earlier close's forgetting would empty the list before these are sent
        closeTimer.restart();
    }

    // Kept until the window is gone (its preview stays off until then; one that asks first, e.g. unsaved work, gets it
    // back after 5 s)
    property var closing: []
    // The ones closeTimer is to close (not every one in closing: an earlier one that asked first isn't asked again)
    property var toClose: []

    Timer {
        id: closeTimer

        interval: 200
        onTriggered: {
            const list = root.toClose;
            root.toClose = [];
            for (const a of list) {
                const w = Hypr.toplevels.values.find(t => t.address === a);
                if (w)
                    root.close(w);
            }
            forgetTimer.restart();
        }
    }

    Timer {
        id: forgetTimer

        interval: 5000
        onTriggered: root.closing = []
    }

    Connections {
        target: Hypr.toplevels
        function onValuesChanged(): void {
            if (root.closing.length)
                root.closing = root.closing.filter(a => Hypr.toplevels.values.some(t => t.address === a));
        }
    }

    function close(win: HyprlandToplevel): void {
        Hypr.dispatch(`hl.dsp.window.close({ window = "address:0x${win.address}" })`);
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: column.implicitHeight + Tokens.padding.small * 2
    height: Math.min(implicitHeight, parent?.height ?? implicitHeight)
    anchors.verticalCenter: parent?.verticalCenter

    color: items.length ? Colours.tPalette.m3surfaceContainer : "transparent"
    radius: Tokens.rounding.full

    Behavior on color {
        CAnim {}
    }

    FileView {
        id: pinsFile

        path: `${Quickshell.env("HOME")}/.config/quickshell/sidedock/pins.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const pins = JSON.parse(text());
                root.pins = Array.isArray(pins) ? pins : []; // (a hand edit that isn't a list: no pins, not a dock that errors)
            } catch (e) {}
        }
    }

    // Scrolls when there are more icons than fit, fading at the cut-off edge
    VerticalFadeFlickable {
        id: flick

        fadeAmount: 0.12
        anchors.fill: parent
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small
        contentHeight: column.implicitHeight
        interactive: contentHeight > height && !root.dragging
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: flick.width
            spacing: 0 // no gaps between the icons

            Repeater {
                id: cells

                // Icons that stay (a pinned app, a window still there) keep their cell when the list changes, e.g. on a
                // workspace switch: rebuilding them all made the dock flicker. uid: one per pinned app / window
                model: ScriptModel {
                    values: root.items
                    objectProp: "uid"
                }

                Item {
                    id: cell

                    required property var modelData
                    required property int index
                    // Until Hyprland reports a focus change (none comes when Caelestia starts), its window list says
                    // which window has focus
                    readonly property bool focused: (modelData.wins ?? []).some(t => root.focusKnown ? t.activated : t.lastIpcObject?.focusHistoryID === 0)
                    readonly property bool dragged: root.dragFrom === index

                    width: column.width
                    opacity: modelData.wins?.length && modelData.wins.every(t => t.workspace?.name?.startsWith("special:minimised")) ? 0.5 : 1  // all minimised: dimmed
                    height: modelData.sep ? Tokens.spacing.medium : width
                    z: dragged ? 10 : 0
                    scale: dragged ? 1.12 : 1

                    transform: Translate {
                        y: cell.dragged ? root.dragY - cell.y - cell.height / 2 : root.dragShift(cell.index)

                        Behavior on y {
                            enabled: !cell.dragged

                            Anim {}
                        }
                    }

                    Behavior on scale {
                        Anim {}
                    }

                    StyledRect {
                        visible: !!cell.modelData.sep
                        anchors.centerIn: parent
                        implicitWidth: parent.width / 2
                        implicitHeight: 1
                        color: Colours.palette.m3outlineVariant
                    }

                    StyledRect {
                        visible: !cell.modelData.sep
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.extraSmall / 2
                        radius: Tokens.rounding.full
                        color: Qt.alpha(Colours.palette.m3primary, cell.focused ? 0.25 : 0)

                        StateLayer {
                            property real dragPressY
                            property bool wasDragged

                            radius: Tokens.rounding.full
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            preventStealing: true

                            onPressed: event => {
                                dragPressY = event.y;
                                wasDragged = false;
                            }
                            onPositionChanged: event => {
                                if (!(pressedButtons & Qt.LeftButton))
                                    return;
                                const y = mapToItem(column, 0, event.y).y;
                                if (!root.dragging && Math.abs(event.y - dragPressY) > 8) {
                                    wasDragged = true;
                                    root.dragFrom = cell.index;
                                    root.dragTo = cell.index;
                                    if (root.popouts)
                                        root.popouts.hasCurrent = false;
                                }
                                if (root.dragging)
                                    root.updateDrag(y);
                            }
                            onReleased: if (root.dragging) root.endDrag()
                            onCanceled: {
                                root.dragFrom = root.dragTo = -1;
                            }
                            onClicked: event => {
                                if (wasDragged)
                                    return;
                                const d = cell.modelData;
                                if (event.button === Qt.MiddleButton) {
                                    if (d.win)
                                        root.closeSoon([d.win]);  // its popout may be showing it
                                } else if (d.win) {
                                    root.bringUp(d);
                                } else if (d.entry) {
                                    Apps.launch(d.entry);
                                }
                            }
                        }
                    }

                    // Icons differ in empty space and shape (a circle or a wide folder looks smaller than a
                    // square), so measure each icon's artwork and scale it to the same visual size, centred.
                    //   bounds: box around the artwork; coverage: how much of the image it fills (0-1);
                    //   reach: distance from the artwork's centre to its farthest pixel (square icons' corners)
                    // (a game with no Steam shortcut: its icon from Steam's cache, else Steam's)
                    readonly property string iconSource: Quickshell.iconPath(modelData.entry?.icon ?? root.steamIcon(modelData.win?.lastIpcObject.class ?? ""), "application-x-executable")
                    property rect bounds: Qt.rect(0.06, 0.06, 0.88, 0.88)
                    property real coverage: 0.77
                    property real reach: 0.62

                    Canvas {
                        visible: false
                        width: 1
                        height: 1
                        onImageLoaded: requestPaint()
                        onPaint: {
                            if (!isImageLoaded(cell.iconSource))
                                return;
                            // Raw pixels of the icon at whatever size the theme gives it
                            const img = getContext("2d").createImageData(cell.iconSource);
                            const w = img.width, h = img.height, d = img.data;
                            let x0 = w, y0 = h, x1 = -1, y1 = -1, alpha = 0;
                            for (let y = 0; y < h; y++)
                                for (let x = 0; x < w; x++) {
                                    const a = d[(y * w + x) * 4 + 3];
                                    alpha += a;
                                    if (a > 24) {
                                        x0 = Math.min(x0, x);
                                        x1 = Math.max(x1, x);
                                        y0 = Math.min(y0, y);
                                        y1 = Math.max(y1, y);
                                    }
                                }
                            if (x1 < 0)
                                return;
                            const cx = (x0 + x1 + 1) / 2, cy = (y0 + y1 + 1) / 2;
                            let reach = 0;
                            for (let y = y0; y <= y1; y++)
                                for (let x = x0; x <= x1; x++)
                                    if (d[(y * w + x) * 4 + 3] > 24)
                                        reach = Math.max(reach, Math.hypot((x + 0.5 - cx) / w, (y + 0.5 - cy) / h));
                            cell.bounds = Qt.rect(x0 / w, y0 / h, (x1 - x0 + 1) / w, (y1 - y0 + 1) / h);
                            cell.coverage = alpha / 255 / (w * h);
                            cell.reach = reach;
                        }
                        Component.onCompleted: if (!cell.modelData.sep) loadImage(cell.iconSource)
                    }

                    IconImage {
                        // Visual size every icon is scaled to (fraction of the cell)
                        readonly property real target: cell.width * 0.56
                        // Visual size of the artwork: mix of its longest side and its area
                        readonly property real extent: Math.sqrt(Math.max(cell.bounds.width, cell.bounds.height) * Math.sqrt(cell.coverage))
                        // ...but small enough that it stays clear of the active ring all round (corners included)
                        readonly property real clearRadius: indicator.radius - indicator.stroke / 2 - 4

                        visible: !cell.modelData.sep
                        asynchronous: true
                        anchors.centerIn: parent
                        anchors.alignWhenCentered: false // don't snap up-left, stay centred in the highlight
                        // Shift so the artwork (not the image) is centred
                        anchors.horizontalCenterOffset: (0.5 - cell.bounds.x - cell.bounds.width / 2) * implicitSize
                        anchors.verticalCenterOffset: (0.5 - cell.bounds.y - cell.bounds.height / 2) * implicitSize
                        implicitSize: Math.round(Math.min(target / Math.max(0.5, extent), clearRadius / Math.max(0.3, cell.reach)))
                        source: cell.iconSource
                    }

                    // Running indicator: a dot on the left per window (up to 5, side by side along the circle). When one
                    // becomes the active window, the dots give way to two lines that trace the circle over the top and
                    // the bottom and meet on the right (and go back the same way)
                    Item {
                        id: indicator

                        readonly property real inset: Tokens.padding.extraSmall / 2
                        readonly property real stroke: 2
                        readonly property real radius: (width - inset * 2 - stroke) / 2
                        property real progress: cell.focused ? 1 : 0

                        anchors.fill: parent
                        visible: !cell.modelData.sep
                        opacity: cell.modelData.win ? 1 : 0

                        // Speeds up as it goes, so the two lines close quickly once past halfway
                        Behavior on progress {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.InQuad
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Repeater {
                            id: dots

                            // Always 5, the unused ones hidden: a changing count rebuilt them on every window change,
                            // which crashed the shell once (Qt rebuilding a Repeater mid-update)
                            readonly property int shown: Math.min(cell.modelData.wins?.length ?? 0, 5)

                            model: 5

                            StyledRect {
                                required property int index

                                visible: index < dots.shown
                                // Its place on the circle (radians from the right, clockwise; the left is pi), 9 px apart
                                readonly property real angle: Math.PI + (index - (dots.shown - 1) / 2) * 9 / indicator.radius

                                x: indicator.width / 2 + indicator.radius * Math.cos(angle) - width / 2
                                y: indicator.height / 2 + indicator.radius * Math.sin(angle) - height / 2
                                rotation: (angle - Math.PI) * 180 / Math.PI // along the circle
                                implicitWidth: 3
                                implicitHeight: 6
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3primary
                                opacity: 1 - Math.min(1, indicator.progress * 6)
                            }
                        }

                        Shape {
                            anchors.fill: parent
                            visible: indicator.progress > 0.001
                            preferredRendererType: Shape.CurveRenderer

                            Arc {
                                direction: 1 // over the top
                            }

                            Arc {
                                direction: -1 // under the bottom
                            }
                        }

                        component Arc: ShapePath {
                            required property int direction

                            strokeColor: Colours.palette.m3primary
                            strokeWidth: indicator.stroke
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: indicator.width / 2
                                centerY: indicator.height / 2
                                radiusX: indicator.radius
                                radiusY: indicator.radius
                                startAngle: 180
                                sweepAngle: direction * 180 * Math.min(1, indicator.progress)
                                moveToStart: true
                            }
                        }
                    }
                }
            }
        }
    }
}
