#!/usr/bin/env python3
# Applies the caelestia-overlay changes to a linked copy of Caelestia (made by caelestia-overlay).
# Each feature is all-or-nothing: if any anchor is missing (new Caelestia version), that feature
# is skipped and the original files stay linked.
#   usage: patch.py <installed caelestia dir> <overlay dir>   "Patched:", "Off:" or "WARNING: ... skipped" per feature
#                                                             (exit 3 when one was skipped: caelestia-overlay keeps the
#                                                             WARNING lines for agros-check)
#          patch.py --list   the features as JSON (the Settings app's Features page, settings caelestia.<id>)
import hashlib
import json
import os
import pwd
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))


def read(rel):
    """The file as it stands: an earlier feature's version if one changed it, else Caelestia's. So features that
    change the same file stack (each one builds on the ones before)."""
    path = os.path.join(dst, rel)
    if os.path.lexists(path) and not os.path.islink(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    try:
        with open(os.path.join(src, rel), encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        raise LookupError(f"{rel} not found") from None  # moved or gone: this feature is skipped, not the whole build


def first(*rels):
    """The first of these files that exists (Caelestia moves files between versions)"""
    for rel in rels:
        if os.path.exists(os.path.join(src, rel)):
            return rel
    raise LookupError(f"{rels[0]} not found")


def swap(text, old, new, what):
    """text with old (which must be there exactly once) replaced by new; LookupError(what) if not."""
    if text.count(old) != 1:
        raise LookupError(what)
    return text.replace(old, new)


def swap_one_of(text, olds, new, what):
    """swap() for the first of olds that's there (a newer Caelestia worded it differently); new: a function of the one
    found, giving its replacement"""
    for old in olds:
        if text.count(old) == 1:
            return text.replace(old, new(old))
    raise LookupError(what)


def insert(text, anchor, new, before=True):
    if text.count(anchor) != 1:
        raise LookupError(anchor.strip().splitlines()[0])
    return text.replace(anchor, new + anchor if before else anchor + new, 1)


def swap_block(text, head, new, what, must=""):
    """text with the QML block starting at head (unique; its first "{" opens the block) up to its closing brace's line
    replaced by new. Only the head has to match, not every line inside (which an update may well touch); must: text
    the block has to hold, so it's still the block meant"""
    if text.count(head) != 1:
        raise LookupError(what)
    start = text.rfind("\n", 0, text.index(head)) + 1
    i, depth = text.index("{", text.index(head)), 0
    for i in range(i, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            break
    else:
        raise LookupError(what)
    end = text.find("\n", i) + 1 or len(text)
    if must not in text[start:end]:
        raise LookupError(what)
    return text[:start] + new + text[end:]


def drop_after(text, anchor, line, what):
    """text without the first line equal to line (stripped) in the 6 lines after the unique anchor"""
    if text.count(anchor) != 1:
        raise LookupError(what)
    pos = text.index(anchor) + len(anchor)
    for _ in range(6):
        nl = text.find("\n", pos)
        if nl < 0:
            break
        if text[pos:nl].strip() == line:
            return text[:pos] + text[nl + 1:]
        pos = nl + 1
    raise LookupError(what)


def append_block(text, block):
    text = text.rstrip()
    if not text.endswith("}"):
        raise LookupError("closing brace")
    return text[: text.rfind("}")] + block


def own(name):
    """One of my files in the overlay dir (a whole new component, not a patch)."""
    with open(os.path.join(here, name), encoding="utf-8") as f:
        return f.read()


def components(*rels):
    """My whole new components (each the overlay's file of the same name) at rels, as files for write(). A Caelestia
    with a file of its own at one skips the feature: written over, Caelestia's parts that use it got mine"""
    for rel in rels:
        if os.path.lexists(os.path.join(src, rel)):
            raise LookupError(f"{rel} is Caelestia's own now")
    return {rel: own(os.path.basename(rel)) for rel in rels}


def write(files):
    # Every file's folder there first: one gone (a Caelestia update moved it) skips the feature before anything is
    # written, not after its other files were (the bar then used a part never made, and the whole shell didn't load)
    for rel in files:
        if not os.path.isdir(os.path.dirname(os.path.join(dst, rel))):
            raise LookupError(f"{os.path.dirname(rel)}/ not found")
    for rel, content in files.items():
        path = os.path.join(dst, rel)
        if os.path.lexists(path):
            os.remove(path)  # a link to the installed file: replace it, never write through it
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)


def launcher():
    # Super menu: hover an app for its heart (favourite) and thumbtack (dock pin) buttons (appitem-block.qml, beside
    # this); its favouriteIcon is the anchor that says the item is still the one the block was written for
    rel = "modules/launcher/items/AppItem.qml"
    s = read(rel)
    if "id: favouriteIcon" not in s:
        raise LookupError("favouriteIcon")
    s = insert(s, "import Quickshell.Widgets\n", "import Quickshell.Io\n", before=False)
    s = append_block(s, own("appitem-block.qml"))
    return {rel: s}


def dock():
    # The bar's "dock" entry (shell.json's bar entries): pinned apps and open windows (Dock.qml), each with a
    # Caelestia-style hover popout (DockMenu.qml), shown through the bar's own popout machinery
    bar = read("modules/bar/Bar.qml")
    bar = insert(bar, '        } else if (id === "activeWindow"', '''        } else if (id === "dock") {
            const dock = ch.item;
            const cell = dock.cellAt(mapToItem(dock, 0, y).y);
            if (cell && !dock.dragging) {
                popouts.dockItem = dock;
                popouts.dockTarget = cell.modelData;
                popouts.currentName = "dock";
                // (its last place once the cell is gone, e.g. its window closed: not an error on every update)
                let last = cell.mapToItem(root, 0, cell.height / 2).y;
                popouts.currentCenter = Qt.binding(() => (dock.flick.contentY, last = cell ? cell.mapToItem(root, 0, cell.height / 2).y : last));
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
''')
    bar = insert(bar, '            DelegateChoice {\n                roleValue: "tray"', '''            DelegateChoice {
                roleValue: "dock"
                delegate: EntryWrapper {
                    Layout.fillHeight: true
                    Layout.preferredHeight: 0

                    Dock {
                        screen: root.screen
                        popouts: root.popouts
                    }
                }
            }
''')

    wrapper = insert(read("modules/bar/popouts/Wrapper.qml"), "    property real currentCenter\n",
                     "    property alias dockTarget: popoutState.dockTarget\n    property alias dockItem: popoutState.dockItem\n",
                     before=False)
    state = insert(read("modules/bar/popouts/PopoutState.qml"), "    property bool hasCurrent\n",
                   "    property var dockTarget\n    property var dockItem\n", before=False)
    content = insert(read("modules/bar/popouts/Content.qml"), '        Popout {\n            name: "bluetooth"', '''        Popout {
            name: "dock"
            sourceComponent: DockMenu {
                popouts: root.popouts
            }
        }

''')

    files = {
        "modules/bar/Bar.qml": bar,
        "modules/bar/popouts/Wrapper.qml": wrapper,
        "modules/bar/popouts/PopoutState.qml": state,
        "modules/bar/popouts/Content.qml": content,
    }
    return files | components("modules/bar/components/Dock.qml", "modules/bar/popouts/DockMenu.qml")


def window_icons():
    """One lookup for every icon of a window (bar workspaces, active window, dock and its popout; the switcher loads
    the same file): ~/.config/quickshell/common/WindowApps.qml, as Icons.windowApps, getAppIcon and
    getAppCategoryIcon through it"""
    rel = "utils/Icons.qml"
    s = read(rel)
    # (Quickshell's own lookup until the file has loaded)
    s = swap(s, "DesktopEntries.heuristicLookup(name)?.icon",
             "(root.windowApps?.appEntry(name) ?? DesktopEntries.heuristicLookup(name))?.icon", "getAppIcon's lookup")
    s = swap(s, "DesktopEntries.heuristicLookup(name)?.categories",
             "(root.windowApps?.appEntry(name) ?? DesktopEntries.heuristicLookup(name))?.categories",
             "getAppCategoryIcon's lookup")
    s = append_block(s, """
    // ---- caelestia-overlay: a window's app and icon, the switcher's lookup too (../common/WindowApps.qml; not an
    // import: Quickshell blocks those from outside this folder) ----
    readonly property var windowApps: windowAppsFile.item
    property Loader windowAppsFile: Loader {
        source: `file://${Quickshell.shellPath("../common/WindowApps.qml")}`
    }
}
""")
    return {rel: s}


def nexus_region():
    """Nexus > Language & region: the weather location picker (the desktop forecast widget's, ../common/PlacePicker.qml,
    in place of Caelestia's "coming soon"), and the system clock: time, network time (NTP), date and time by hand, time
    zone (timedatectl)"""
    rel = "modules/nexus/pages/LanguageAndRegion.qml"
    s = read(rel)
    s = insert(s, "import Quickshell\n", "import Quickshell.Io\n", before=False)
    # Caelestia's "coming soon" card only (its block, which must still say so), not up to the next section's comment:
    # a section an update puts in between, or that comment gone further down, was cut out with it
    s = swap_block(s, "        // Placeholder until the map-based location picker lands\n", own("nexus-weather-block.qml"),
                   "the weather location placeholder", must="coming soon")
    clock = """            first: true
            last: true
            label: Tr.tr("Clock format")"""
    s = swap(s, clock, clock.replace("            last: true\n", ""), "the clock format row")
    s = insert(s, "            onSelected: item => GlobalConfig.services.clockFormat = item.value\n        }\n",
               own("nexus-time-block.qml"), before=False)
    return {rel: s} | components("modules/nexus/common/SuggestRow.qml")


def dock_space():
    # The dock turned off (or left out by an update): its entry in the bar's list (shell.json) matched nothing and its
    # space went, moving the workspaces down and the tray and clock up. Kept as space instead, so the rest stays put
    bar = read("modules/bar/Bar.qml")
    if 'roleValue: "dock"' in bar:
        return {}
    return {"modules/bar/Bar.qml": insert(bar, '            DelegateChoice {\n                roleValue: "logo"', """            DelegateChoice {
                roleValue: "dock"
                delegate: EntryWrapper {
                    Layout.fillHeight: true
                }
            }
""")}


def bluetooth():
    # Bar Bluetooth popout: the link button only toggled "connected", which fails for a device
    # that was never paired. Pair (and trust) it first, then connect once pairing finishes.
    rel = "modules/bar/popouts/Bluetooth.qml"
    s = read(rel)
    old = "                    onClicked: device.modelData.connected = !device.modelData.connected\n"
    s = swap(s, old, """                    onClicked: {
                        const d = device.modelData;
                        if (d.paired) {
                            d.connected = !d.connected;
                            return;
                        }
                        // caelestia-overlay: new device, pair it first
                        const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                        if (adapter)
                            adapter.pairable = true;
                        d.trusted = true;
                        d.pair();
                    }
""", "connect button")
    s = insert(s, "            MaterialIcon {\n                text: Icons.getBluetoothIcon(device.modelData.icon)", """            // caelestia-overlay: connect as soon as a new device finishes pairing
            Connections {
                function onPairedChanged(): void {
                    if (device.modelData.paired && !device.modelData.connected)
                        device.modelData.connected = true;
                }

                target: device.modelData
            }

""")
    return {rel: s}


def spotify_tray():
    # Spotify always marks its tray icon "Passive", which Caelestia hides; show it anyway.
    # Both the icons (Tray.qml) and the popout menus (Content.qml) filter the list: both must match,
    # or hovering one icon opens the next one's menu
    out = {}
    for rel, n in (("modules/bar/components/Tray.qml", 1), ("modules/bar/popouts/Content.qml", 2)):
        s = read(rel)
        if s.count("i.status !== Status.Passive") != n:
            raise LookupError(f"Passive filter in {rel}")
        out[rel] = s.replace("i.status !== Status.Passive", '(i.status !== Status.Passive || i.id === "spotify-client")')
    return out


def favourites_az():
    # Super menu: favourites at the top, then the other apps, each in alphabetical order (Caelestia orders them by
    # how often they're opened)
    rel = "modules/launcher/services/Apps.qml"
    s = read(rel)
    old = "    list: appDb.apps\n"
    return {rel: swap(s, old, """    list: {
        const fav = GlobalConfig.launcher.favouriteApps;
        const isFav = e => Strings.testRegexList(fav, (e.entry ?? e).id);
        const name = e => String((e.entry ?? e).name ?? e.name).toLowerCase();
        const az = (a, b) => name(a).localeCompare(name(b));
        return [...appDb.apps.filter(isFav).sort(az), ...appDb.apps.filter(e => !isFav(e)).sort(az)];
    }
""", old.strip())}


def launcher_by_kind():
    # Super menu: an app is found by what it is too (its launcher entry's generic name and keywords), not only by its
    # name: "term" found nothing, foot's name is Foot (a "Terminal"), nor "files" Thunar. Those found by name first, as
    # before; then the others, as Caelestia's own >g and >k prefixes find them, those whose generic name, then keywords,
    # have a word starting with the text (a plural's "s" aside) first: "term" Micro (a Text Editor, its keyword
    # "terminal") came before Foot (a Terminal), "files" Desktop Settings ("dotfiles") before Thunar (a File Manager)
    rel = "modules/launcher/services/Apps.qml"
    old = """            if (!search.startsWith(`${prefix}t `))
                return query(search).map(e => e.entry);
"""
    return {rel: swap(read(rel), old, """            // caelestia-overlay: then the apps found by what they are (generic name, keywords), after those by name
            if (!search.startsWith(`${prefix}t `)) {
                const byName = query(search).map(e => e.entry);
                const q = ` ${search.trim().toLowerCase().replace(/\\s+/g, " ").replace(/s$/, "")}`;
                const text = t => ` ${String(t ?? "").toLowerCase().replace(/[\\s,;.\\/_-]+/g, " ")}`;
                const word = t => text(t).includes(q);
                const rank = e => word(e.genericName) ? 0 : word(e.keywords) ? 1
                    : text(e.genericName).includes(q.slice(1)) || text(e.keywords).includes(q.slice(1)) ? 2 : 3;
                // (a plain look at each app, not query() with other keys: changing keys rebuilt the whole search index,
                // twice a keystroke. No flatMap: QML's JavaScript has none, and the menu came up empty)
                const found = list.filter(e => !byName.includes(e.entry) && rank(e) < 3);
                const byKind = found.filter(e => rank(e) === 0).concat(found.filter(e => rank(e) === 1),
                    found.filter(e => rank(e) === 2)).map(e => e.entry);
                return byName.concat(byKind);
            }
""", "the Super menu's search by name")}


def tray_menu_fallback():
    # Right-clicking a tray icon with no standard menu (Wine apps: the Epic Games launcher) opens the app's own menu
    # (~/.local/bin/tray-menu: its ContextMenu call, which Quickshell doesn't make); it did nothing
    rel = "modules/bar/components/TrayItem.qml"
    s = read(rel)
    s = insert(s, "import Quickshell.Services.SystemTray\n", "import Quickshell\n")
    s = swap(s, """        else
            modelData.secondaryActivate();""", """        else if (!modelData.hasMenu)
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/tray-menu", modelData.id]);
        else
            modelData.secondaryActivate();""", "right-click branch")
    return {rel: s}


def tray_az():
    # Tray icons in alphabetical order (by name, else id). The icons (Tray.qml) and the popout menus (Content.qml)
    # each list them, and must agree, or hovering one icon opens another's menu: all lists get the same order.
    # Builds on the Spotify tray feature's version of the files
    old = "!GlobalConfig.bar.tray.hiddenIcons.includes(i.id))"
    new = old + '.sort((a, b) => (a.title || a.id).localeCompare(b.title || b.id, undefined, { sensitivity: "base" }))'
    out = {}
    for rel, n in (("modules/bar/components/Tray.qml", 1), ("modules/bar/popouts/Content.qml", 2)):
        t = read(rel)
        if t.count(old) != n:
            raise LookupError(f"tray list in {rel}")
        out[rel] = t.replace(old, new)
    return out


def internal_brightness():
    # Brightness slider only on built-in screens: external monitors use their own buttons/menu
    rel = "modules/osd/Content.qml"
    s = read(rel)
    if s.count("Config.osd.enableBrightness") != 2:
        raise LookupError("Config.osd.enableBrightness")
    s = s.replace("Config.osd.enableBrightness", "(Config.osd.enableBrightness && root.builtIn)")
    s = insert(s, "    required property real brightness\n", """    readonly property bool builtIn: /^(eDP|LVDS|DSI)/.test(monitor?.modelData?.name ?? "")
""", before=False)
    # ...nor the popup for an external screen's brightness change (the bar's scroll, its late DDC read): it showed with
    # volume alone. Its level is only the slider's, not shown there
    w = "modules/osd/Wrapper.qml"
    osd = insert(read(w), "        function onBrightnessChanged(): void {\n", """            if (!/^(eDP|LVDS|DSI)/.test(root.screen?.name ?? ""))
                return;
""", before=False)
    return {rel: s, w: osd}


def bar_space_refit():
    # The bar's reserved space changed (its "always shown" setting, a screen left without a bar, the bar dragged out):
    # maximised and snapped windows fitted to the new free part (windows.lua's dots.refit_placed_soon). Hyprland has no
    # event for a layer's reserved space changing in place, as Caelestia's bar does
    rel = "modules/drawers/Exclusions.qml"
    s = read(rel)
    return {rel: swap(s, """        anchors.left: true
        exclusiveZone: root.bar.exclusiveZone
""", """        anchors.left: true
        exclusiveZone: root.bar.exclusiveZone
        onExclusiveZoneChanged: Quickshell.execDetached(["hyprctl", "eval", "dots.refit_placed_soon()"])
""", "the bar's exclusion zone")}


def logo_inert():
    # Bar logo: just the logo, no click (Caelestia's opens the launcher, which Super does already)
    rel = "modules/bar/components/OsIcon.qml"
    s = read(rel)
    old = """    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const screenState = ShellState.forActive();
            screenState.launcher = !screenState.launcher;
        }
    }

"""
    return {rel: swap(s, old, "", "logo MouseArea")}


def safe_triangle():
    # Bar popouts: moving the pointer from a bar button towards its open popout (inside the triangle from the
    # pointer to the popout's top and bottom corners) doesn't switch to the popout of buttons passed on the way
    rel = "modules/drawers/Interactions.qml"
    s = read(rel)
    s = insert(s, "    property bool utilitiesShortcutActive\n", """
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

    function aimPopout(x: real, y: real): void {
        aimY = y;
        const a = aimAnchor;
        const w = panels.popoutsWrapper;
        if (popouts.hasCurrent && w.width > 0 && w.height > 0 && a.x >= 0) {
            const px = bar.implicitWidth + w.x;
            const top = borderThickness + w.y;
            // Only the part of the popout within a 2:1 slope of the anchor (~63° up or down): with a tall popout,
            // a triangle to its far corners would swallow moves along the bar to the next buttons
            const reach = (px - a.x) * 2;
            const t = Math.max(top, a.y - reach);
            const b = Math.min(top + w.height, a.y + reach);
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

    Timer {
        id: aimTimer

        interval: 300
        onTriggered: {
            root.aimAnchor = Qt.point(root.mouseX, root.mouseY);
            if (root.containsMouse && root.mouseX < root.bar.implicitWidth)
                root.bar.checkPopout(root.aimY);
        }
    }
""", before=False)
    old = """        if (x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else"""
    s = swap(s, old, """        if (x < bar.implicitWidth) {
            root.aimPopout(x, y);
        } else""", "checkPopout on hover")
    return {rel: s}


def steam_installed_only():
    # Steam's tray menu: the recent games at the top only show installed games (not Proton, runtimes,
    # uninstalled games); list from ~/.local/bin/steam-installed-games, refreshed each time the menu opens
    content = read("modules/bar/popouts/Content.qml")
    old = "                        trayItem: trayMenu.modelData.menu"  # (not its qmllint comment, which changes)
    content = swap(content, old, "                        trayId: trayMenu.modelData.id\n" + old, "TrayMenu trayItem")

    rel = "modules/bar/popouts/TrayMenu.qml"
    s = read(rel)
    s = insert(s, "import Quickshell.Widgets\n", "import Quickshell.Io\n", before=False)
    s = insert(s, "    required property QsMenuHandle trayItem\n", """    property string trayId
    // Steam: installed game names (caelestia-overlay)
    property var steamGames: null

    Process {
        running: root.trayId === "steam"
        command: [Quickshell.env("HOME") + "/.local/bin/steam-installed-games"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.steamGames = JSON.parse(text);
                } catch (e) {}
            }
        }
    }

    // Hide entries of Steam's recent-games section (before the first separator) that aren't installed games
    function hideEntry(menu: var, entries: var, index: int): bool {
        if (trayId !== "steam" || !steamGames || menu.isSubMenu)
            return false;
        const sep = entries.findIndex(e => e.isSeparator);
        if (sep < 0 || index > sep)
            return false;
        if (index === sep) // the separator itself: hide it if no game is left above it
            return !entries.slice(0, sep).some(e => steamGames.includes(e.text));
        return !steamGames.includes(entries[index].text);
    }
""", before=False)
    old = """            StyledRect {
                id: item

                required property QsMenuEntry modelData
"""
    s = swap(s, old, old + """                required property int index

                visible: !root.hideEntry(menu, menuOpener.children.values, index)
""", "menu item delegate")
    old = "                implicitHeight: modelData.isSeparator ? 1 : children.implicitHeight\n"
    s = swap(s, old, "                implicitHeight: !visible ? 0 : modelData.isSeparator ? 1 : children.implicitHeight\n", "item implicitHeight")
    return {"modules/bar/popouts/Content.qml": content, rel: s}


def lock_tint():
    # The lock screen's blurred wallpaper dimmed like the login screen's (shell.json: lock.useWallpaper)
    rel = "modules/lock/LockSurface.qml"
    s = read(rel)
    s = insert(s, "    Component {\n        id: screencopyBackground\n", """    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3surface, 0.45)
        opacity: background.opacity
    }

""")
    return {rel: s}


def lock_instant_fail():
    # A wrong password on the lock screen said at once, not after about 2 s: nodelay on the pam_unix and pam_faillock
    # lines (each asks for that delay) in the lock's own PAM config (Caelestia's assets/pam.d/passwd, which its
    # PamContext reads from the shell's folder: the login screen, sudo and the TTYs keep theirs). pam_faillock otherwise
    # stays as it is: tries still counted, and too many lock the account out as before
    rel = "assets/pam.d/passwd"
    lines, unix, faillock = read(rel).split("\n"), 0, 0
    for i, line in enumerate(lines):
        words = line.split()
        if words[:1] == ["auth"] and ("pam_unix.so" in words or "pam_faillock.so" in words):
            unix += "pam_unix.so" in words
            faillock += "pam_faillock.so" in words
            if "nodelay" not in words:
                lines[i] = line.rstrip() + " nodelay"
    if unix != 1 or faillock < 1:
        raise LookupError("the lock's pam_unix and pam_faillock lines (assets/pam.d/passwd)")
    return {rel: "\n".join(lines)}


def lock_cursor():
    # A blinking text cursor after the lock screen's password characters (before the placeholder when empty)
    rel = "modules/lock/center/InputField.qml"
    s = read(rel)
    # Room for the cursor left of the placeholder: the field is only as wide as the placeholder, and clips
    old = "    readonly property alias placeholderWidth: nonAnimPlaceholder.width\n"
    s = swap(s, old, "    readonly property real cursorGap: 2 + Tokens.spacing.small\n"
                       "    readonly property real placeholderWidth: nonAnimPlaceholder.width + cursorGap\n", "placeholderWidth")
    s = insert(s, "        anchors.verticalCenterOffset: 1\n\n        text: nonAnimPlaceholder.text\n",
               "        anchors.horizontalCenterOffset: root.cursorGap / 2\n")
    s = insert(s, "    component CharItem: Item {\n", """    Rectangle {
        id: textCursor

        x: root.buffer ? charList.x + charList.width - charList.implicitHeight / 2 + Tokens.spacing.extraSmall
                       : placeholder.x - width - Tokens.spacing.small
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 2
        implicitHeight: charList.implicitHeight * 1.6
        radius: 1
        color: Colours.palette.m3primary
        visible: !root.pam.passwd.active && root.pam.state !== Pam.MaxTries

        // Solid while typing, then blinks
        Connections {
            function onBufferChanged(): void {
                blink.restart();
            }

            target: root.pam
        }

        SequentialAnimation on opacity {
            id: blink

            running: textCursor.visible // (not while it checks the password, nor after too many tries)
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 0 }
            PauseAnimation { duration: 530 }
            NumberAnimation { to: 0; duration: 120 }
            PauseAnimation { duration: 410 }
        }
    }

""")
    return {rel: s}


def scroll_lock():
    # A Scroll Lock icon with Caps and Num Lock at the bottom of the bar (state: ScrollLock.qml)
    icons = read("modules/bar/components/status/LockStatus.qml")
    if "keyboard_capslock_badge" not in icons or "looks_one" not in icons or "ScrollLock" in icons:
        raise LookupError("LockStatus.qml")
    status = read("modules/bar/components/StatusIcons.qml")
    old = "            return !Hypr.capsLock && !Hypr.numLock;\n"
    status = swap(status, old, "            return !Hypr.capsLock && !Hypr.numLock && !ScrollLock.on;\n", "lockStatus collapsed")
    popout = read("modules/bar/popouts/LockStatus.qml")
    popout = insert(popout, """        text: Hypr.numLock ? Tr.tr("Num lock enabled") : Tr.tr("Num lock disabled")\n    }\n""", """
    StyledText {
        text: ScrollLock.on ? "Scroll lock enabled" : "Scroll lock disabled"
    }
""", before=False)
    files = {"modules/bar/components/StatusIcons.qml": status, "modules/bar/popouts/LockStatus.qml": popout}
    files |= components("services/ScrollLock.qml")
    files["modules/bar/components/status/LockStatus.qml"] = own("LockStatus.qml")
    return files


def updates_button():
    # Super menu: a "check for updates" button right of the search bar (~/.local/bin/update-apps --check-now). Its
    # icon spins while checking (closed and opened again meanwhile too); then a notification says the result, and
    # clicking it opens Settings' Updates
    rel = "modules/launcher/Content.qml"
    t = read(rel)
    t = insert(t, "import QtQuick\n", "import Quickshell\nimport Quickshell.Io\n", before=False)
    old = """        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
"""
    t = swap(t, old, """        anchors.left: parent.left
        anchors.right: updatesButton.left
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.rightMargin: Tokens.spacing.small
""", "search bar anchors")
    t = insert(t, "    SearchBar {\n", """    // caelestia-overlay: check for updates; the icon spins until the check is done
    IconButton {
        id: updatesButton

        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.verticalCenter: search.verticalCenter
        implicitWidth: search.implicitHeight
        implicitHeight: search.implicitHeight
        // Just the icon, in the accent colour (a highlight on hover, no background)
        type: IconButton.Text
        inactiveOnColour: Colours.palette.m3primary
        icon: "sync"
        // (the check itself in AgrosUpdateCheck, which outlives the menu: reopened while it runs, still spinning)
        onClicked: AgrosUpdateCheck.start()

        RotationAnimation {
            target: updatesButton.label
            property: "rotation"
            running: AgrosUpdateCheck.running
            from: 360
            to: 0
            duration: 1000
            loops: Animation.Infinite
            onStopped: updatesButton.label.rotation = 0
        }
    }

""")
    return {rel: t, **components("services/AgrosUpdateCheck.qml")}


def settings_button():
    # Super menu: a settings button left of the updates one (updates_button), opening the settings (Caelestia's Nexus,
    # with AgrOS's pages); the menu closes as it opens
    rel = "modules/launcher/Content.qml"
    t = read(rel)
    t = insert(t, "import QtQuick\n", "import qs.modules.nexus\n", before=False)
    t = swap(t, "        anchors.right: updatesButton.left\n", "        anchors.right: settingsButton.left\n", "search bar anchors")
    t = insert(t, "    // caelestia-overlay: check for updates; the icon spins until the check is done\n", """    // caelestia-overlay: the settings (Nexus)
    IconButton {
        id: settingsButton

        anchors.right: updatesButton.left
        anchors.verticalCenter: search.verticalCenter
        implicitWidth: search.implicitHeight
        implicitHeight: search.implicitHeight
        // Just the icon, in the accent colour, as the updates button
        type: IconButton.Text
        inactiveOnColour: Colours.palette.m3primary
        icon: "settings"
        onClicked: {
            root.screenState.launcher = false;
            WindowFactory.create(null, {});
        }
    }

""")
    return {rel: t}


def nexus_pages():
    # AgrOS's settings in Caelestia's own settings (Nexus), its pages there among Nexus's own in their categories: the
    # page it opens on (AgrosHome.qml), Display (AgrosDisplay.qml: Nexus's own is a TODO), Updates (AgrosUpdates.qml, in
    # Nexus's placeholder), and dots-settings's pages (AgrosPage.qml); what's left of dots-settings's other pages (what
    # Nexus doesn't show itself) under Nexus's Wallpaper & style, Panels and Services (AgrosSections.qml). Nexus's two
    # lists (the pages, and the component for each) go by position: each one goes into both at the same place, and the
    # bar's popout, which opens Nexus at a page by its position, is told where its pages went
    def entry(label, icon, desc, cat):
        return f"""        {{
            label: "{label}", // caelestia-overlay: AgrOS's
            icon: "{icon}",
            description: "{desc}",
            category: "{cat}"
        }},
"""

    def comp(label, page):
        body = page if page.endswith("}") else f"""AgrosPage {{
                title: "{label}"
                pageId: "{page}"
            }}"""
        return f"""        Component {{
            // {label} (caelestia-overlay: AgrOS's)
            {body}
        }},
"""

    # (start; start of Connectivity; end of Connectivity; end of System; start of Shell)
    places = [("        // Appearance\n", True, [("Home", "home", "The settings most looked for", "home", "AgrosHome {}")]),
              ("        // Connectivity\n", False, [("Display", "monitor", "Screens, their arrangement, night light", "connectivity", "AgrosDisplay {}")]),
              ("        // System\n", True, [("Mouse & keyboard", "mouse", "Pointer, touchpad, keyboard layout", "connectivity", "input")]),
              ("        // Shell\n", True, [("Features", "auto_awesome", "Games, Lutris, the shell's extras", "system", "features"),
                                          ("Startup", "rocket_launch", "Apps started at login", "system", "startup"),
                                          # (Caelestia's options no other page has: the old Settings app's "All Caelestia
                                          # options", less the ones shown elsewhere)
                                          ("Advanced", "tune", "Every other option of the shell's", "system", """AgrosPage {
                title: "Advanced"
                pageId: "caelestia"
                advanced: true
            }""")]),
              ("        // Shell\n", False, [("Windows", "select_window", "Floating or tiling, focus, title bars", "shell", "windows"),
                                           ("Shortcuts", "keyboard", "Keyboard shortcuts", "shell", "keys")])]
    reg, comps = read("modules/nexus/PageRegistry.qml"), read("modules/nexus/PageCompRegistry.qml")
    for anchor, before, pages in places:
        reg = insert(reg, anchor, "".join(entry(l, i, d, c) for l, i, d, c, _ in pages), before=before)
        comps = insert(comps, anchor, "".join(comp(l, page) for l, _, _, _, page in pages), before=before)
    # Updates: Nexus's placeholder (the first under System, Plugins' the second)
    comps = swap(comps, """        // System
        Component {
            PlaceholderComp {}
        },
""", """        // System
        Component {
            // Updates (caelestia-overlay: AgrOS's)
            AgrosUpdates {}
        },
""", "updates placeholder")

    # The pages in AgrOS's order, under its titles (the nav list's groups), each with the dots-settings pages whose
    # settings its search finds it by (agros). Reordered in both lists alike; Nexus's own pages not named here (a new
    # one in an update) go at the end of System
    order = [("home", "", ["home"]),
             ("look", "Look & feel", ["palette", "select_window", "dock_to_bottom"]),
             ("devices", "Devices", ["monitor", "volume_up", "mouse", "devices_other", "wifi"]),
             ("apps", "Apps & shortcuts", ["apps", "rocket_launch", "keyboard"]),
             ("system", "System", ["update", "auto_awesome", "build", "globe", "tune", "info"])]
    # (Nexus's Plugins page: a placeholder, nothing on it yet: left out until Caelestia fills it)
    drop = {"extension"}
    agros = {"palette": ["look", "panels"], "dock_to_bottom": ["panels", "bar", "launcher", "session"], "build": ["notifs", "region"],
             "monitor": ["screens"], "mouse": ["input"], "auto_awesome": ["features"], "rocket_launch": ["startup"],
             "select_window": ["windows"], "keyboard": ["keys"], "tune": ["caelestia"]}

    def items(text, head):
        """The list at head ("readonly property list<var> pages: ["): where its items start and end, and each item
        (its lines, from its opening line to its "}," at the list's indent), comments between them dropped"""
        start = text.index(head) + len(head)
        end = text.index("\n    ]\n", start) + 1
        out, cur = [], []
        for line in text[start:end].splitlines(keepends=True):
            if not cur and line.startswith("        ") and line.rstrip().endswith("{") and not line.startswith("         "):
                cur = [line]
            elif cur:
                # (the last one may have no comma)
                if line in ("        },\n", "        }\n"):
                    cur.append("        },\n")
                    out.append("".join(cur))
                    cur = []
                else:
                    cur.append(line)
        if cur or not out:
            raise LookupError(f"the list {head.strip()}")
        return start, end, out

    rs, re_, pages = items(reg, "    readonly property list<var> pages: [\n")
    cs, ce, pcomps = items(comps, "    readonly property list<Component> pageComps: [\n")
    if len(pages) != len(pcomps):
        raise LookupError("Nexus's page lists out of step")
    icons = [re.search(r'^ {12}icon: "([^"]+)"', p, re.M).group(1) for p in pages]
    rank = {icon: (i, j, cat) for i, (cat, _, ics) in enumerate(order) for j, icon in enumerate(ics)}
    placed = sorted((k for k in range(len(pages)) if icons[k] not in drop), key=lambda k: rank.get(icons[k], (len(order) - 1, 99, "system"))[:2])
    new_pages = []
    for k in placed:
        page = re.sub(r'^( {12}category: )"[^"]*"', f'\\1"{rank.get(icons[k], (0, 0, "system"))[2]}"', pages[k], flags=re.M)
        page = re.sub(r'^( {12}icon: "[^"]+",\n)', lambda m: m.group(1) + f"            agros: {json.dumps(agros.get(icons[k], []))},\n", page, flags=re.M)
        new_pages.append(page)
    reg = reg[:rs] + "".join(new_pages) + reg[re_:]
    comps = comps[:cs] + "".join(pcomps[k] for k in placed) + comps[ce:]
    reg = insert(reg, "    readonly property list<var> pages: [\n", f"""    // caelestia-overlay: the titles over the nav list's groups (AgrOS's, by category)
    readonly property var titles: {json.dumps({cat: title for cat, title, _ in order if title})}
""")

    # The bar's popout opens Nexus at these pages: by their icon, as they've moved
    wrapper = swap(read("modules/bar/popouts/Wrapper.qml"), """["appearance", "network", "bluetooth", "audio"].indexOf(root.queuedMode)""",
                   """PageRegistry.pages.findIndex(p => p.icon === ({ appearance: "palette", network: "wifi", bluetooth: "devices_other", audio: "volume_up" })[root.queuedMode]) // caelestia-overlay: by icon (AgrOS moved them)""",
                   "popout's nexus pages")

    # The nav list: a title over each group; the search over it (Nexus's did nothing) keeps the pages whose name, what
    # they're about, or one of AgrOS's settings on them has what's typed
    state = insert(read("modules/nexus/NexusState.qml"), "    property bool searchOpen\n", """    property string searchText // caelestia-overlay: the nav search's
    signal clearSearch // caelestia-overlay: a search result's page opened (AgrosSearch.qml)
""", before=False)
    pane = insert(read("modules/nexus/NavPane.qml"), """            value: searchField.text.length > 0
        }
""", """
        // caelestia-overlay: what's searched (the nav list keeps the pages it finds; AgrOS's settings found, in the page's
        // place: AgrosSearch.qml), and cleared when one's page is opened from there
        Binding {
            target: root.nState
            property: "searchText"
            value: searchField.text
        }

        Connections {
            function onClearSearch(): void {
                searchField.text = "";
            }

            target: root.nState
        }
""", before=False)
    nav = read("modules/nexus/navpane/NavLocations.qml")
    nav = swap(nav, """    required property NexusState nState
""", """    required property NexusState nState
    // caelestia-overlay: which pages the search finds (all of them without one)
    readonly property var shown: PageRegistry.pages.map(p => AgrosSettings.matches(p, nState.searchText))
""", "nav shown")
    nav = swap(nav, """                readonly property bool isCategoryStart: index === 0 || PageRegistry.pages[index - 1].category !== modelData.category
                readonly property bool isCategoryEnd: index === list.model.length - 1 || PageRegistry.pages[index + 1].category !== modelData.category
""", """                // caelestia-overlay: its group's first and last of those shown, rounded there while searching too
                readonly property bool isCategoryStart: !PageRegistry.pages.some((p, j) => j < index && root.shown[j] && p.category === modelData.category)
                readonly property bool isCategoryEnd: !PageRegistry.pages.some((p, j) => j > index && root.shown[j] && p.category === modelData.category)
""", "nav item group ends")
    nav = swap(nav, """                readonly property bool isCurrentPage: index === root.nState.currentPageIdx
""", """                readonly property bool isCurrentPage: index === root.nState.currentPageIdx
                // caelestia-overlay: found by the search; the title over its group (none while searching)
                readonly property bool found: root.shown[index] ?? true
                readonly property string groupTitle: isCategoryStart && !root.nState.searchOpen ? PageRegistry.titles[modelData.category] ?? "" : ""
""", "nav item state")
    nav = swap(nav, """                Layout.topMargin: index !== 0 && isCategoryStart ? Tokens.spacing.medium : 0
""", """                Layout.topMargin: (index !== root.shown.indexOf(true) && isCategoryStart ? Tokens.spacing.medium : 0) + (groupTitle ? groupLabel.implicitHeight + Tokens.spacing.small : 0)
                visible: found
""", "nav item margin")
    nav = swap(nav, """                StateLayer {
                    id: stateLayer
""", """                // caelestia-overlay: its group's title, over it
                StyledText {
                    id: groupLabel

                    visible: item.groupTitle !== ""
                    x: Tokens.padding.large
                    y: -implicitHeight - Tokens.spacing.small
                    text: item.groupTitle
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.large
                }

                StateLayer {
                    id: stateLayer
""", "nav item title")

    # Nexus: the shortcut recorder over it; closed, the changes that wait for it applied (the shell's restart)
    nexus = read("modules/nexus/Nexus.qml")
    nexus = insert(nexus, "import qs.modules.nexus\n", "import qs.modules.nexus.common\n", before=False)
    nexus = insert(nexus, "import QtQuick\n", "import QtQuick.Layouts\n", before=False)
    nexus = insert(nexus, "    signal close\n", """    // caelestia-overlay: AgrOS's changes waiting for Nexus to close (the shell's restart), applied now
    Component.onDestruction: AgrosSettings.flush()

""", before=False)
    # (what the search finds of AgrOS's settings, in the page's place while something's typed; and AgrOS's settings read
    # again every few seconds while Nexus is open, so one changed elsewhere shows as it is)
    nexus = insert(nexus, "    Pages {\n", """    // caelestia-overlay: AgrOS's settings the search finds, in the page's place (AgrosSearch.qml)
    AgrosSearch {
        id: agrosSearch

        anchors.fill: agrosPages
        visible: nState.searchText.trim().length >= 2
        nState: nState
    }

    // caelestia-overlay: AgrOS's settings read again while open: one changed elsewhere shows as it is
    Timer {
        running: true
        repeat: true
        interval: 4000
        onTriggered: AgrosSettings.refresh()
    }

""")
    nexus = insert(nexus, "    Pages {\n", """        id: agrosPages // caelestia-overlay

        visible: !agrosSearch.visible
""", before=False)
    # (on every page, Home's and Caelestia's own too: why the last change failed; a change that restarts the shell, held
    # until Nexus closes, or now, Nexus opened again at the same page once it's back)
    nexus = insert(nexus, "    NavPane {\n", """    // caelestia-overlay: the last change that failed; the shell's restart waiting for Nexus to close (AgrosSettings.qml)
    StyledRect {
        anchors.horizontalCenter: agrosPages.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.extraLarge
        z: 5
        visible: AgrosSettings.error !== "" || AgrosSettings.restartHeld
        width: Math.min(agrosPages.width, held.implicitWidth + Tokens.padding.medium + Tokens.padding.largeIncreased)
        implicitHeight: held.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: AgrosSettings.error ? Colours.palette.m3errorContainer : Colours.palette.m3secondaryContainer

        RowLayout {
            id: held

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
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

            TextButton {
                visible: !AgrosSettings.error && AgrosSettings.restartHeld
                type: ButtonBase.Tonal
                text: "Restart now"
                onClicked: {
                    AgrosSettings.reopenAt = PageRegistry.pages[nState.currentPageIdx]?.icon ?? "";
                    root.close();
                }
            }
        }
    }

    // caelestia-overlay: recording a shortcut (AgrOS's Shortcuts)
    AgrosKeyCapture {
        anchors.fill: parent
        z: 10
    }

""")

    # What's left of dots-settings's pages, at the end of Nexus's own (their content: the page's one ColumnLayout)
    def fold(page, sections):
        t = read(page)
        i = t.rstrip().rfind("\n    }\n}")
        if i < 0 or "AgrosSections" in t:
            raise LookupError(f"{page}: its end")
        return t[:i + 1] + f"""
        // caelestia-overlay: AgrOS's settings Nexus doesn't show itself
        AgrosSections {{
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            firstHeader: false
{sections}        }}
""" + t[i + 1:]

    # The bar's edge (AgrOS's: bar_side) first on Nexus's Taskbar page, where the bar's settings are, not at the end of
    # Panels' AgrOS sections; there still if that page has changed
    tb = "modules/nexus/pages/panels/TaskbarPanel.qml"
    try:
        taskbar = swap(read(tb), """        // Behaviour
        SectionHeader {
            first: true
""", """        // caelestia-overlay: which edge it's on (AgrOS's setting: the shell restarts with it there)
        SectionHeader {
            first: true
            text: "Position"
        }

        AgrosRow {
            first: true
            last: true
            key: "bar.side"
        }

        // Behaviour
        SectionHeader {
""", "the taskbar page's first section")
        # ...and the dock among its components, after the clock: its page (AgrosBarDock.qml) the sub-page after the
        # clock's, the 12th (Panels' stack: its 6 pages, then the bar's 5 components)
        taskbar = swap(taskbar, """        NavRow {
            last: true
            icon: "schedule"
            text: Tr.tr("Clock")
            subtext: Tr.tr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }
""", """        NavRow {
            icon: "schedule"
            text: Tr.tr("Clock")
            subtext: Tr.tr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // caelestia-overlay: AgrOS's dock
        NavRow {
            last: true
            icon: "apps"
            text: "Dock"
            subtext: "Pinned apps and open windows"
            onClicked: root.nState.openSubPage(11)
        }
""", "the taskbar page's clock row")
        comps = swap(comps, """                Component {
                    BarClock {}
                }
""", """                Component {
                    BarClock {}
                }
                Component {
                    AgrosBarDock {}
                }
""", "the clock's sub-page")
    except LookupError:
        taskbar = None
    folded = {
        "modules/nexus/pages/WallpaperAndStyle.qml": fold("modules/nexus/pages/WallpaperAndStyle.qml", """            pageIds: ["look", "panels"]
            onlyGroups: ["Fonts (the shell's)", "Windows", "Shell", "Desktop"]
"""),
        "modules/nexus/pages/PanelsPage.qml": fold("modules/nexus/pages/PanelsPage.qml", """            pageIds: ["panels", "bar", "launcher", "session"]
            skipGroups: ["Desktop"]
""" + ("""            skipKeys: ["bar.side"]
""" if taskbar else "")),
        "modules/nexus/pages/ServicesPage.qml": fold("modules/nexus/pages/ServicesPage.qml", """            pageIds: ["notifs", "region"]
"""),
    }
    # Wallpaper & style: those screens in the place of its one preview, with more than one screen
    style = folded["modules/nexus/pages/WallpaperAndStyle.qml"]
    # (the preview by its id, whatever it is: StyledClippingRect, on Caelestia's main a ClipRect; left as it is if gone)
    head = re.search(r"\n        ([A-Za-z.]+) \{\n            id: wallWrapper\n", style)
    if head:
        style = style.replace(head.group(0), f"""
        // caelestia-overlay: the screens, each with its wallpaper (AgrosScreenWalls.qml), with more than one; the
        // preview with one
        AgrosScreenWalls {{
            id: screenWalls

            Layout.fillWidth: true
        }}

        {head.group(1)} {{
            id: wallWrapper

            visible: !screenWalls.visible
""", 1)
    # The dark theme switch as Settings' light, dark or AMOLED black (AgrOS's, amoled); at the end of the page's AgrOS
    # sections if that's moved
    dark = """        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            text: Tr.tr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }
"""
    if style.count(dark) == 1:
        style = style.replace(dark, """        // caelestia-overlay: light, dark or AgrOS's AMOLED black, Settings' (look.mode)
        AgrosRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            key: "look.mode"
        }
""")
    folded["modules/nexus/pages/WallpaperAndStyle.qml"] = style
    # Wallpapers: the screens first, as arranged, each with its wallpaper, one clicked to give it its own
    # (AgrosScreenWalls.qml); at the page's end if its buttons have moved
    walls = read("modules/nexus/pages/wallandstyle/WallpaperSelect.qml")
    screens = """        // caelestia-overlay: the screens, each with its wallpaper (AgrosScreenWalls.qml)
        AgrosScreenWalls {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.large
        }

"""
    if walls.count("        ButtonRow {\n") == 1:
        walls = insert(walls, "        ButtonRow {\n", screens)
    else:
        end = walls.rstrip().rfind("\n    }\n}")
        if end < 0:
            raise LookupError("WallpaperSelect.qml: its end")
        walls = walls[:end + 1] + "\n" + screens + walls[end + 1:]
    folded["modules/nexus/pages/wallandstyle/WallpaperSelect.qml"] = walls

    # Wallpaper & style's Colours: Nexus's is a "page under construction"; AgrOS's colour settings there (the scheme,
    # light or dark, its variant, colours from the wallpaper). One Caelestia has made itself is left as it is
    colours = read("modules/nexus/pages/wallandstyle/ColourSelect.qml")
    if "Page under construction" in colours:
        folded["modules/nexus/pages/wallandstyle/ColourSelect.qml"] = """// caelestia-overlay: AgrOS's colour settings (dots-settings's look page's Colours), Nexus's page being a placeholder
import QtQuick
import QtQuick.Layouts
import Caelestia.I18n
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Colours")
    isSubPage: true

    AgrosSections {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        pageIds: ["look"]
        onlyGroups: ["Colours"]
    }
}
"""

    files = components("services/AgrosSettings.qml", "modules/nexus/common/AgrosRow.qml",
                       "modules/nexus/common/AgrosSections.qml", "modules/nexus/common/AgrosKeyCapture.qml",
                       "modules/nexus/common/AgrosSkeleton.qml", "modules/nexus/common/AgrosScreenWalls.qml",
                       "modules/nexus/common/AgrosSearch.qml",
                       "modules/nexus/pages/AgrosPage.qml", "modules/nexus/pages/AgrosHome.qml",
                       "modules/nexus/pages/AgrosDisplay.qml", "modules/nexus/pages/AgrosUpdates.qml",
                       *(["modules/nexus/pages/AgrosBarDock.qml"] if taskbar else []))
    # Caelestia's options Nexus's own pages set (GlobalConfig.bar.persistent...), by their path: not shown again
    covered = set()
    for dirpath, _, names in os.walk(os.path.join(src, "modules/nexus")):
        for name in names:
            if name.endswith(".qml"):
                with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                    covered |= set(re.findall(r"\b(?:GlobalConfig|Config)\.([a-zA-Z]+(?:\.[a-zA-Z]+)+)", f.read()))
    sections = "modules/nexus/common/AgrosSections.qml"
    files[sections] = swap(files[sections], "    readonly property var covered: []\n",
                           f"    readonly property var covered: {json.dumps(sorted(covered))}\n", "covered options")
    return {"modules/nexus/PageRegistry.qml": reg, "modules/nexus/PageCompRegistry.qml": comps,
            "modules/bar/popouts/Wrapper.qml": wrapper, "modules/nexus/Nexus.qml": nexus,
            "modules/nexus/NexusState.qml": state, "modules/nexus/NavPane.qml": pane,
            "modules/nexus/navpane/NavLocations.qml": nav, **folded, **files, **({tb: taskbar} if taskbar else {})}


def nexus_snappy():
    # Settings (Nexus) quicker and wider: a page's change and a sub-page's in a step quicker each (Caelestia's slowest
    # fades, waited for one after the other, made each click feel late); the pages as wide as the window allows, less
    # a margin, where Nexus kept them a column with the rest empty (maximised, most of the window); its wallpapers'
    # pictures read once at about their size (a new size on every change of width read each one again)
    def quicker(t):
        return (t.replace("Anim.DefaultEffects", "Anim.FastEffects").replace("Anim.SlowEffects", "Anim.DefaultEffects")
                .replace("durations.expressiveDefaultEffects", "durations.expressiveFastEffects"))

    pages, stack = read("modules/nexus/Pages.qml"), read("modules/nexus/common/StackPage.qml")
    if "Anim.SlowEffects" not in pages or "Anim.SlowEffects" not in stack:
        raise LookupError("page transitions")
    # A page's skeleton (AgrosSkeleton.qml) the moment it's chosen, the page made a frame later (made at once, the
    # window showed nothing, and took no clicks, until it was done)
    pages = insert(pages, "import qs.modules.nexus\n", "import qs.modules.nexus.common\n", before=False)
    pages = swap(pages, """    function loadPage(idx: int): void {
        if (currentItem)
            currentItem.destroy();

""", """    // caelestia-overlay: the skeleton first, drawn, then the page made
    property int pendingIdx: -1

    function loadPage(idx: int): void {
        // (the page there, or being made, not made again: Nexus opened at a page asked for it twice, the second
        // copy without what the first had been handed: settings_open_at)
        if (idx === pendingIdx)
            return;
        if (currentItem)
            currentItem.destroy();
        currentItem = null;
        pendingIdx = idx;
        buildTimer.restart();
    }

    function buildPage(idx: int): void {
""", "page loading")
    # (the page out of sight until it's whole, made bit by bit, the skeleton showing meanwhile)
    pages = swap(pages, """        const incubator = comp.incubateObject(container, {
            nState
        });

        const attach = () => {
            incubator.object.anchors.fill = container;
""", """        const incubator = comp.incubateObject(container, {
            nState,
            visible: false
        });

        const attach = () => {
            // (another page chosen while this one was being made: not shown under it)
            if (idx !== pendingIdx)
                return incubator.object.destroy();
            incubator.object.anchors.fill = container;
            incubator.object.visible = true;
""", "page made out of sight")
    pages = insert(pages, "        Component.onCompleted: root.loadPage(root.nState.currentPageIdx)\n", """
        // caelestia-overlay: the page's skeleton until it's made
        AgrosSkeleton {
            anchors.fill: parent
            visible: !root.currentItem
        }
""", before=False)
    pages = insert(pages, "    SequentialAnimation {\n        id: switchAnim\n", """    Timer {
        id: buildTimer

        interval: 16 // (a frame: the skeleton drawn first)
        onTriggered: root.buildPage(root.pendingIdx)
    }

""")
    base = swap(read("modules/nexus/common/PageBase.qml"),
                "    readonly property int cappedWidth: Math.min(Tokens.sizes.nexus.maxContentWidth, width)\n",
                "    readonly property int cappedWidth: Math.min(width, Math.max(Tokens.sizes.nexus.maxContentWidth, Math.round(width * 0.92))) // caelestia-overlay: wider in a wide window\n",
                "page width")
    # (Caelestia's main sizes them otherwise already: left as it is there)
    wall = read("modules/nexus/common/WallItem.qml")
    old_size = """                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(width * dpr, height * dpr);
                }
                retainWhileLoading: true
"""
    wall = wall if old_size not in wall else swap(wall, """                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(width * dpr, height * dpr);
                }
                retainWhileLoading: true
""", """                // caelestia-overlay: in steps of 256 px (each new size read the picture again)
                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(Math.ceil(width * dpr / 256) * 256, Math.ceil(height * dpr / 256) * 256);
                }
                retainWhileLoading: true
""", "wallpaper picture size")
    # The wallpaper's preview no taller than 360 (with the page as wide as the window, it took half of it); as many
    # wallpapers in a row as fit at about 260 each (Nexus's own count at the least)
    style = swap(read("modules/nexus/pages/WallpaperAndStyle.qml"),
                 "                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);\n",
                 "                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height, 360); // caelestia-overlay: no taller than 360\n",
                 "wallpaper preview size")
    grids = {}
    for rel in ("modules/nexus/pages/wallandstyle/WallpaperSelect.qml", "modules/nexus/pages/wallandstyle/WallpaperCategory.qml"):
        grids[rel] = swap(read(rel), "columns: Config.nexus.wallpapersPerRow\n",
                          "columns: Math.max(Config.nexus.wallpapersPerRow, Math.floor(width / 260)) // caelestia-overlay: as many as fit\n",
                          "wallpapers per row")
    return {"modules/nexus/Pages.qml": quicker(pages), "modules/nexus/common/StackPage.qml": quicker(stack),
            "modules/nexus/common/PageBase.qml": base, "modules/nexus/common/WallItem.qml": wall,
            "modules/nexus/pages/WallpaperAndStyle.qml": style, **grids}


def nexus_history():
    # Settings (Nexus) browsed like a browser: back and forward beside a page's title (the pages, and their sub-pages,
    # as they were shown; a sub-page's back arrow was the only way back), the mouse's back and forward buttons too; no
    # close button in its own window (Hyprland's close, and its title bar's, do that)
    state = read("modules/nexus/NexusState.qml")
    state = swap(state, """    function openSubPage(idx: int): void {
        subPageIdxStack.push(idx);
        subPageOpened(idx);
    }

    function closeSubPage(): void {
        subPageClosed();
        subPageIdxStack.pop();
    }

    onCurrentPageIdxChanged: subPageIdxStack.length = 0
""", """    function openSubPage(idx: int): void {
        subPageIdxStack.push(idx);
        subPageOpened(idx);
        remember(); // caelestia-overlay
    }

    function closeSubPage(): void {
        subPageClosed();
        subPageIdxStack.pop();
        remember(); // caelestia-overlay
    }

    // caelestia-overlay: where back and forward go: the pages, with their sub-pages, as they were shown
    property var here: ({ page: currentPageIdx, subs: [] })
    property var backStack: []
    property var forwardStack: []
    property bool travelling

    function remember(): void {
        const now = { page: currentPageIdx, subs: Array.from(subPageIdxStack) };
        if (now.page === here.page && String(now.subs) === String(here.subs))
            return;
        if (!travelling) {
            backStack = backStack.concat([here]);
            forwardStack = [];
        }
        here = now;
    }

    function go(to: var): void {
        travelling = true;
        if (to.page !== currentPageIdx) {
            currentPageIdx = to.page;
            subPageIdxStack = to.subs; // (opened by the page, made a frame later: StackPage)
        } else {
            let same = 0;
            while (same < Math.min(to.subs.length, subPageIdxStack.length) && to.subs[same] === subPageIdxStack[same])
                same++;
            while (subPageIdxStack.length > same)
                closeSubPage();
            for (const idx of to.subs.slice(same))
                openSubPage(idx);
        }
        remember();
        travelling = false;
    }

    function back(): void {
        if (!backStack.length)
            return;
        const to = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
        forwardStack = forwardStack.concat([here]);
        go(to);
    }

    function forward(): void {
        if (!forwardStack.length)
            return;
        const to = forwardStack[forwardStack.length - 1];
        forwardStack = forwardStack.slice(0, -1);
        backStack = backStack.concat([here]);
        go(to);
    }

    onCurrentPageIdxChanged: {
        subPageIdxStack.length = 0;
        remember(); // caelestia-overlay
    }
""", "history")

    nexus = read("modules/nexus/Nexus.qml")
    # (its shape none: a blob's drawn hidden or not)
    nexus = swap(nexus, """        implicitWidth: windowBtn.implicitWidth + (root.nState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small) * 2
        implicitHeight: windowBtn.implicitHeight + (root.nState.isWindow ? Tokens.padding.extraSmall : Tokens.padding.small)
""", """        // caelestia-overlay: none in a window (no close button there)
        implicitWidth: root.nState.isWindow ? 0 : windowBtn.implicitWidth + Tokens.padding.small * 2
        implicitHeight: root.nState.isWindow ? 0 : windowBtn.implicitHeight + Tokens.padding.small
""", "close button's shape")
    nexus = swap(nexus, """    IconButton {
        id: windowBtn
""", """    IconButton {
        id: windowBtn

        visible: !root.nState.isWindow // caelestia-overlay: no close button in a window
""", "close button")
    nexus = insert(nexus, "    NavPane {\n", """    // caelestia-overlay: the mouse's back and forward buttons (other buttons, and the wheel, go to what's under it)
    MouseArea {
        anchors.fill: parent
        z: 9
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onPressed: mouse => mouse.button === Qt.BackButton ? root.nState.back() : root.nState.forward()
    }

""")

    base = swap(read("modules/nexus/common/PageBase.qml"), """            Loader {
                visible: active
                active: root.isSubPage
                asynchronous: true
                sourceComponent: IconButton {
                    icon: "arrow_back"
                    font: Tokens.font.icon.medium
                    type: IconButton.Tonal
                    isRound: true
                    inactiveColour: Colours.tPalette.m3surfaceContainerHigh
                    inactiveOnColour: Colours.palette.m3onSurfaceVariant
                    onClicked: root.nState.closeSubPage()
                }
            }
""", """            // caelestia-overlay: back and forward, as browsed (out of a sub-page as before when nothing's before it)
            HistoryButton {
                visible: root.nState.backStack.length > 0 || root.isSubPage
                icon: "arrow_back"
                onClicked: root.nState.backStack.length ? root.nState.back() : root.nState.closeSubPage()
            }

            HistoryButton {
                visible: root.nState.forwardStack.length > 0
                icon: "arrow_forward"
                onClicked: root.nState.forward()
            }
""", "back button")
    base = insert(base, "    VerticalFadeFlickable {\n", """    component HistoryButton: IconButton {
        font: Tokens.font.icon.medium
        type: IconButton.Tonal
        isRound: true
        inactiveColour: Colours.tPalette.m3surfaceContainerHigh
        inactiveOnColour: Colours.palette.m3onSurfaceVariant
    }

""")
    return {"modules/nexus/NexusState.qml": state, "modules/nexus/Nexus.qml": nexus, "modules/nexus/common/PageBase.qml": base}


def settings_open_at():
    # Settings (Nexus) opened at one of its pages, by the page's icon: "nexus openPage update" (the Super menu's "Update
    # apps"); and at Updates with what a check just found, starting the update or not ("nexus updates true <file>":
    # update-apps' notifications). In place of the old Updates app, which opened so
    rel = first("modules/Shortcuts.qml", "daemons/Shortcuts.qml")
    ipc = swap(read(rel), """        function open(): void {
            WindowFactory.create();
        }

        target: "nexus"
""", """        function open(): void {
            WindowFactory.create();
        }

        // caelestia-overlay: at a page, by its icon; at Updates with a check's list (a file; "" for none), started or not
        function openPage(icon: string): void {
            AgrosSettings.openAt = icon;
            WindowFactory.create();
        }

        function updates(start: bool, list: string): void {
            AgrosSettings.updatesStart = start;
            AgrosSettings.updatesList = list;
            openPage("update");
        }

        target: "nexus"
""", "nexus ipc")
    nexus = insert(read("modules/nexus/Nexus.qml"), "    signal close\n", """
    // caelestia-overlay: opened at a page (nexus openPage)
    Component.onCompleted: {
        const i = PageRegistry.pages.findIndex(p => p.icon === AgrosSettings.openAt);
        AgrosSettings.openAt = "";
        if (i >= 0)
            nState.currentPageIdx = i;
    }
""", before=False)
    return {rel: ipc, "modules/nexus/Nexus.qml": nexus}


def tray_click():
    # Collapsed tray: a click on its arrow opens it (not hovering). It closes on a click on the bar and its panels
    # outside the tray, or, as before, when the pointer leaves the bar for a window (not for a tray icon's menu). No
    # focus grab to close it on clicks in windows: that kept every window from scrolling while it was open
    # Builds on the dock and safe triangle features' versions of Bar.qml and Interactions.qml
    bar = read("modules/bar/Bar.qml")
    bar = swap(bar, """        if (ch?.entryId !== "tray")
            closeTray();

""", "", "close tray on hover")
    bar = swap(bar, """                popouts.hasCurrent = false;
                tray.expanded = true;
""", """                popouts.hasCurrent = false;
""", "open tray on hover")
    bar = insert(bar, "    function checkPopout(y: real): void {\n", """    // caelestia-overlay: whether y is on the tray (a click anywhere else closes it)
    function trayAt(y: real): bool {
        return (childAt(width / 2, y) as EntryWrapper)?.entryId === "tray";
    }

""")

    wrapper = read("modules/bar/BarWrapper.qml")
    wrapper = insert(wrapper, """    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }
""", """
    function trayAt(y: real): bool {
        return (content.item as Bar)?.trayAt(y) ?? false;
    }
""", before=False)

    inter = read("modules/drawers/Interactions.qml")
    inter = swap(inter, "    onPressed: event => dragStart = Qt.point(event.x, event.y)\n", """    onPressed: event => {
        dragStart = Qt.point(event.x, event.y);
        // caelestia-overlay: a click anywhere but on the tray closes it
        if (!(event.x < bar.implicitWidth && bar.trayAt(event.y)))
            bar.closeTray();
    }
""", "onPressed")

    tray = read("modules/bar/components/Tray.qml")
    tray = insert(tray, "        sourceComponent: Item {\n", """            // caelestia-overlay: the arrow opens and closes the tray (not hovering), with the power button's highlight
            StateLayer {
                parent: root.parent // outside the tray, which clips its contents (it cut the circle in half)
                z: 1 // in front: the tray's hidden icons lie under the arrow while it's collapsed and would take the click
                visible: root.visible
                anchors.fill: undefined
                x: root.x + expandIcon.x + (expandIcon.width - width) / 2
                y: root.y + expandIcon.y + expandIconInner.y + expandIconInner.height / 2 - height / 2
                implicitWidth: implicitHeight
                implicitHeight: expandIconInner.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.full
                onClicked: root.expanded = !root.expanded
            }

""", before=False)
    return {"modules/bar/Bar.qml": bar, "modules/bar/BarWrapper.qml": wrapper,
            "modules/drawers/Interactions.qml": inter, "modules/bar/components/Tray.qml": tray}


def lock_refresh():
    # Caps/Num Lock badges: Caelestia reads the locks once at start, then only on those keys, so a wrong state at
    # login (Caps shown on when it's off) stays. Read them again when the keymap or config changes, and once more
    # shortly after start, all inside the shell (Caelestia's main fix, PR #1899, binds a remapped Caps key only)
    rel = "services/Hypr.qml"
    s = read(rel)
    s = insert(s, "                root.reloadDynamicConfs();\n", "                extras.refreshDevices();\n", before=False)
    s = insert(s, """            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {""",
               """            } else if (n === "activelayout") {
                extras.refreshDevices();
""")
    s = append_block(s, """
    Timer {
        running: true
        interval: 2000
        onTriggered: extras.refreshDevices()
    }
}
""")
    return {rel: s}


def sidebar_notifs_only():
    # The notification sidebar (top-right hover) alone: Caelestia also opens the utilities panel under it (keep awake,
    # screen recording, quick toggles). That panel opens on its own (bottom-right corner, Super+K), with the sidebar or not
    rel = "modules/utilities/Wrapper.qml"
    s = read(rel)
    # (Caelestia's main names the utilities' own part first, showUtils)
    s = swap_one_of(s, ("    readonly property bool shouldBeActive: screenState.sidebar || (screenState.utilities",
                        "    readonly property bool shouldBeActive: screenState.sidebar || showUtils\n"),
                    lambda old: old.replace("screenState.sidebar || ", ""), "utilities shouldBeActive")
    # Its contents stay built while it's hidden, so its height is known before it ever opens: the sidebar ends where
    # its top is (sidebar_shape), on any screen
    old = "        active: root.shouldBeActive || root.visible\n"
    s = swap(s, old, "        active: true\n", "utilities loader")
    # ...and laid out: Qt doesn't lay out hidden items (the quick toggles row came out 46 px short). Closed, it sits
    # below the screen and fully transparent, which Qt doesn't draw
    old = "    visible: offsetScale < 1\n"
    s = swap(s, old, "    visible: true\n", "utilities visible")
    return {rel: s}


def amoled():
    # Settings' AMOLED black (look.amoled in ~/.config/dots/settings.json, read as it changes): in dark mode the scheme's
    # backgrounds pure black, the bar, its border and the panels (background, surface and the lowest containers), the
    # surfaces on them darkened to match; the scheme read again as it's turned on or off
    rel = "services/Colours.qml"
    c = swap(read(rel), """    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);
""", """    // caelestia-overlay (amoled): Settings' AMOLED black, and the scheme last read, to read again as it changes
    property bool amoled
    property string lastScheme

    onAmoledChanged: if (lastScheme)
        load(lastScheme, false)

    // (on unless the settings say it's off: none, or unreadable, on)
    function amoledFrom(text: string): void {
        try {
            root.amoled = JSON.parse(text)?.["look.amoled"] !== false;
        } catch (e) {
            root.amoled = true;
        }
    }

    FileView {
        id: amoledSettings

        path: `${Quickshell.env("HOME")}/.config/dots/settings.json`
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.amoledFrom(text())
        onLoadFailed: root.amoled = true
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);
        if (!isPreview)
            lastScheme = data;
""", "the scheme's loading")
    c = swap(c, """            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }
""", """            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }

        // caelestia-overlay (amoled): dark, its backgrounds black, the surfaces on them (cards, pills, the bar's
        // entries) darkened to match, still apart from it and each other, their tint kept
        if (amoled && scheme.mode !== "light") {
            for (const name of ["m3background", "m3surface", "m3surfaceDim", "m3surfaceContainerLowest", "m3surfaceContainerLow"])
                if (colours.hasOwnProperty(name))
                    colours[name] = "#000000";
            for (const name of ["m3surfaceContainer", "m3surfaceContainerHigh", "m3surfaceContainerHighest", "m3surfaceVariant", "m3surfaceBright"])
                if (colours.hasOwnProperty(name))
                    colours[name] = Qt.darker(colours[name], 1.7);
        }
    }
""", "the scheme's colours")
    # Both read before the shell's first frame, not as they load: it showed Caelestia's default dark for a moment (its
    # border and bar grey, then black) as it started
    c = swap(c, """    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
""", """    FileView {
        id: schemeFile

        path: `${Paths.state}/scheme.json`
        blockLoading: true // caelestia-overlay (amoled): read at the start, below
        watchChanges: true
""", "the scheme's file")
    c = swap(c, "    Component.onCompleted: root.requestReloadHyprRules()\n", """    Component.onCompleted: {
        root.requestReloadHyprRules();
        // caelestia-overlay (amoled): the settings, then the scheme, read now: the first frame in their colours
        root.amoledFrom(amoledSettings.text());
        const scheme = schemeFile.text();
        if (scheme)
            root.load(scheme, false);
    }
""", "the colours' start")
    return {rel: c}


def cursor_blink_rest():
    # A text field's cursor stops blinking 10 s after the last key, click or focus in it, solid till the next (GTK's
    # way): each blink redrew its window (the Super menu's, the bar's with a bottom bar) about 13 times, and the shell's
    # other windows once, so an open Super menu kept the graphics card busy for as long as it stayed open
    rel = "components/controls/TextFieldBase.qml"
    s = swap(read(rel), """                    enableBlink.restart();
                }
            }
""", """                    enableBlink.restart();
                    blinking.restart(); // caelestia-overlay (cursor_blink_rest)
                }
            }

            // caelestia-overlay (cursor_blink_rest): blinking again as it's focused
            function onActiveFocusChanged(): void {
                if (root.activeFocus)
                    blinking.restart();
            }
""", "the cursor's moves")
    s = swap(s, """            interval: 500
            onTriggered: cursor.disableBlink = false
        }
""", """            interval: 500
            onTriggered: cursor.disableBlink = false
        }

        // caelestia-overlay (cursor_blink_rest): how long it blinks after the last key, click or focus; then solid
        Timer {
            id: blinking

            interval: 10000
            onTriggered: cursor.opacity = 1
        }
""", "the cursor's blink start")
    s = swap(s, "            running: root.activeFocus && root.cursorVisible && !cursor.disableBlink\n",
             "            running: root.activeFocus && root.cursorVisible && !cursor.disableBlink && blinking.running\n",
             "the cursor's blink")
    return {rel: s}


def gauges_settle():
    # The dashboard's gauges (CPU, memory, storage; the Performance tab's too): a change under 5 points straight there,
    # larger ones glide as before. Each reading (every second or so) glided, one into the next, so an open dashboard
    # never stopped redrawing
    glide = re.compile(r"^( *)Behavior on clampedVal \{\n\1    Anim \{\}\n\1\}\n", re.M)
    out, n = {}, 0
    for rel in ("modules/dashboard/dash/Resources.qml", "modules/dashboard/performance/HeroCard.qml",
                "modules/dashboard/performance/MemoryCard.qml", "modules/dashboard/performance/StorageCard.qml"):
        def settled(m):
            nonlocal n
            n += 1
            i, g = m[1], f"glide{n}"
            return (f"{i}Behavior on clampedVal {{\n{i}    id: {g}\n\n"
                    f"{i}    // caelestia-overlay (gauges_settle): under 5 points, straight there\n"
                    f"{i}    Anim {{\n{i}        duration: Math.abs({g}.targetValue - ({g}.targetProperty.object as CircularProgress).clampedVal) < 0.05 ? 0 : Tokens.anim.durations.expressiveDefaultSpatial\n{i}    }}\n{i}}}\n")
        s, k = glide.subn(settled, read(rel))
        if not k:
            raise LookupError(f"the gauge's animation in {rel}")
        out[rel] = s
    return out


def notifs_neutral():
    # Notification icons, badges and counts in one neutral colour (Caelestia uses the error colour for critical ones
    # and the theme's secondary, pink here, for normal ones): every urgency gets the low-urgency colours. The same in
    # the pop-ups and the sidebar
    value = r"Colours\.(?:t?[Pp]alette\.\w+|layer\(Colours\.palette\.\w+, \d+\))"
    who = r"root\.(?:modelData\.)?urgency"
    three = re.compile(rf"{who} === NotificationUrgency\.Critical \? {value} : {who} === NotificationUrgency\.Low \? ({value}) : {value}")
    two = re.compile(rf"{who} === NotificationUrgency\.Critical \? {value} : ({value})")
    out = {}
    for rel in ("modules/sidebar/NotifGroup.qml", "modules/notifications/Notification.qml"):
        s, n3 = three.subn(r"\1", read(rel))
        s, n2 = two.subn(r"\1", s)
        if not n3 + n2 or "NotificationUrgency.Critical ?" in s:
            raise LookupError(f"urgency colours in {rel}")
        out[rel] = s
    return out


def notif_click():
    # Clicking a notification runs its action (the one named "default", which is what a click means, else its only
    # one), like its button: in the notification center too, where a click did nothing (Caelestia only does it on
    # pop-ups, and only for a notification with a single action). And it brings the app that sent it to the front, or
    # opens it, as on Windows: dots.focus_app in ~/.config/caelestia/user/windows.lua (apps can't raise themselves from a
    # notification: no activation token)
    pick = 'actions.find(a => a.identifier === "default") ?? (actions.length === 1 ? actions[0] : null)'
    data = insert(read("services/NotifData.qml"), """    property bool popup
""", """    // caelestia-overlay: the app that sent this, to the front (or opened): dots.focus_app in user/windows.lua
    // launch false: its action already started something (the app itself opening twice could undo that)
    function openApp(launch: bool): void {
        // Many apps name only themselves ("Proton VPN"), not their launcher entry: found by that name then, as
        // Caelestia finds their icon (not for no name: that finds an unrelated app)
        const entry = notification?.desktopEntry || (appName ? (DesktopEntries.heuristicLookup(appName)?.id ?? "") : "");
        // (JSON's quoting as Lua's: the same but for control characters, \\u00XX in JSON, which Lua can't read)
        const lua = s => JSON.stringify(String(s ?? "").replace(/[\\x00-\\x1f]/g, " "));
        Quickshell.execDetached(["hyprctl", "eval", `dots.focus_app(${lua(entry)}, ${lua(appName)}, ${launch})`]);
    }

""")
    popup = swap(read("modules/notifications/Notification.qml"), """            if (actions.length === 1)
                actions[0].invoke();
""", f"""            // invoke?.(): restored notifications (after a restart) keep their actions without it
            const action = {pick};
            action?.invoke?.();
            root.modelData.openApp(!action?.invoke);
""", "pop-up click")
    center = insert(read("modules/sidebar/NotifGroupList.qml"), """
            ParallelAnimation {
                running: notif.modelData?.closed ?? false
""", f"""            // caelestia-overlay: a click runs the notification's action and brings its app forward, as on its pop-up
            onClicked: event => {{
                if (!GlobalConfig.notifs.actionOnClick || event.button !== Qt.LeftButton)
                    return;
                const actions = modelData?.actions ?? [];
                const action = {pick};
                action?.invoke?.();
                modelData?.openApp(!action?.invoke);
            }}
""")
    return {"services/NotifData.qml": data, "modules/notifications/Notification.qml": popup,
            "modules/sidebar/NotifGroupList.qml": center}


def sidebar_shape():
    # Notification sidebar: no divider at its bottom, and it ends where the utilities panel (bottom right) starts
    # instead of running to the bottom of the screen
    content = read("modules/sidebar/Content.qml")
    old = """
        StyledRect {
            Layout.topMargin: Tokens.padding.large - layout.spacing
            Layout.fillWidth: true
            implicitHeight: 1

            color: Colours.tPalette.m3outlineVariant
        }
"""
    content = swap(content, old, "", "sidebar divider")
    panels = read("modules/drawers/Panels.qml")
    old = """        anchors.top: notifications.bottom
        anchors.bottom: utilities.top
"""
    panels = swap(panels, old, """        anchors.top: notifications.bottom
        anchors.bottom: parent.bottom
        // Its grey card ends where that panel's background starts (the card sits its inner bottom spacing above this
        // edge): that panel's height whether open or not (sidebar_notifs_only keeps it built), less that spacing
        anchors.bottomMargin: utilities.implicitHeight - (Tokens.padding.large - 2)
""", "sidebar anchors")
    # The clear button floats over the last notification: a stronger shadow sets it apart on the dark cards
    dock = read("modules/sidebar/NotifDock.qml")
    old = "                level: clearBtn.stateLayer.containsMouse ? 4 : 3\n"
    dock = swap(dock, old, "                level: 5\n                color: Qt.alpha(Colours.palette.m3shadow, 1)\n", "clear button shadow")
    # Where it meets the utilities panel (both open, with Super+K): joined as Caelestia joins them, not smoothed together
    # (that bulged out on the left, their edges being in line) and with square corners there; only while both are open
    # (Caelestia's: while the sidebar is, as the utilities panel always opened with it), else both keep rounded corners
    window = read("modules/drawers/ContentWindow.qml")
    joined = "panels.sidebar.offsetScale > 0.08 || panels.utilities.offsetScale > 0.08 ? [] : [%s]"
    corner = "Math.max(0, Math.min(1, Math.max(panels.sidebar.offsetScale, panels.utilities.offsetScale) / 0.3)) * radius"
    # ...and the volume panel's shape takes no room while it's closed or the sidebar is open: its zero-width shape at the
    # sidebar's left edge (mid-height, right where the shorter sidebar now ends) made a sag at the sidebar's bottom-left
    # corner, or a dot under it
    for old, new in (("""            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
""", f"""            exclude: {joined % 'utilsBg'}
            bottomLeftRadius: {corner}
"""), ("""            implicitWidth: panels.osd.width
""", """            implicitWidth: panels.osd.width
            implicitHeight: panels.osd.offsetScale < 1 && panels.sidebar.offsetScale === 1 ? panels.osdWrapper.height : 0
"""), ("""            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
""", f"""            exclude: {joined % 'sidebarBg'}
            topLeftRadius: {corner}
""")):
        window = swap(window, old, new, "sidebar/utilities corner join")
    # Free-standing now, so the same gap under the notifications card as at its left (it had none: the panel ran on
    # into the utilities one)
    wrapper = read("modules/sidebar/Wrapper.qml")
    old = "        anchors.bottomMargin: 0\n"
    wrapper = swap(wrapper, old, "        anchors.bottomMargin: anchors.leftMargin - 2\n", "sidebar bottom margin")
    return {"modules/sidebar/Content.qml": content, "modules/drawers/Panels.qml": panels,
            "modules/sidebar/NotifDock.qml": dock, "modules/drawers/ContentWindow.qml": window,
            "modules/sidebar/Wrapper.qml": wrapper}


def sidebar_alone():
    # The notification sidebar is shorter now, so panels that sat beside it look wrong:
    # - not while the power menu (session) is shown: it doesn't open, and closes if the power menu opens
    # - the volume/brightness slider closes at once when it opens (beside the shorter sidebar it hung below it)
    sidebar = swap(read("modules/sidebar/Wrapper.qml"),
                   "    readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled\n",
                   "    readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled && !screenState.session\n",
                   "sidebar shouldBeActive")
    inter = swap_one_of(read("modules/drawers/Interactions.qml"),
                        ("            if (Config.sidebar.showOnHover) {\n",
                         "            if (Config.sidebar.showOnHover && Config.sidebar.enabled) {\n"),
                        lambda old: old.replace(") {", " && !screenState.session) {"), "sidebar hover")
    osd = read("modules/osd/Wrapper.qml")
    osd = swap(osd, "!(screenState.utilities && Config.utilities.enabled)\n",
               "!(screenState.utilities && Config.utilities.enabled) && !screenState.sidebar\n", "osd shouldBeActive")
    osd = swap(osd, "    visible: offsetScale < 1\n", "    visible: offsetScale < 1 && !screenState.sidebar\n", "osd visible")
    # The closed power menu's shape (full size, pushed behind the sidebar) hung out below the shorter sidebar as a
    # dark column: it takes no room while closed
    window = swap(read("modules/drawers/ContentWindow.qml"), """            implicitWidth: panels.session.width
""", """            implicitWidth: panels.session.width
            implicitHeight: panels.session.offsetScale < 1 ? panels.sessionWrapper.height : 0
""", "session shape")
    return {"modules/sidebar/Wrapper.qml": sidebar, "modules/drawers/Interactions.qml": inter,
            "modules/osd/Wrapper.qml": osd, "modules/drawers/ContentWindow.qml": window}


def sidebar_from_top():
    # The notification sidebar slides down from the top, like the utilities panel slides up from the bottom (it came
    # in from the right). Closed, it waits above the screen; hovering the top edge over it opens it
    wrapper = swap(read("modules/sidebar/Wrapper.qml"), "    anchors.rightMargin: (-implicitWidth - 5) * offsetScale\n",
                   "    anchors.rightMargin: 0\n", "sidebar slide")
    panels = swap(read("modules/drawers/Panels.qml"), """        anchors.topMargin: -notifications.anchors.topMargin
""", """        // Both edges move together: closed, it's its bottom edge's distance from the top (plus 5) up, out of sight
        readonly property real slide: (parent.height - utilities.implicitHeight + (Tokens.padding.large - 2) + 5) * offsetScale
        // ...except at the end of opening, as the curve overshoots (slide below 0): its top stays on the border (going
        // past, it came away from it for a moment, an inward notch at its top-left); its bottom springs as before
        anchors.topMargin: -notifications.anchors.topMargin - Math.max(0, slide)
""", "sidebar top")
    panels = swap(panels, "        anchors.bottomMargin: utilities.implicitHeight - (Tokens.padding.large - 2)\n",
                  "        anchors.bottomMargin: utilities.implicitHeight - (Tokens.padding.large - 2) + slide\n",
                  "sidebar bottom")
    # Opened from the top edge above it plus the top of the right edge, as far as the corner's rounding: the mirror of
    # the utilities panel's bottom-right trigger (not down the right edge as far as the popups reach)
    inter = read("modules/drawers/Interactions.qml")
    old = "                const showSidebarHover = x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x) && y <= sidebarTriggerY;\n"
    if inter.count(old) != 2:
        raise LookupError("sidebar hover trigger")
    inter = inter.replace(old, "                const showSidebarHover = y < Math.max(Config.border.minThickness, Config.border.thickness) + Config.border.rounding && withinPanelWidth(panels.sidebar, x, y);\n")
    # Its grey card hangs from the top border, as it looks while sliding down: flush with the top (no gap), its top
    # corners square. Open, it had its own rounded top corners a few pixels under the border, an inward notch at the
    # top-left that showed only once it was fully down
    wrapper = insert(wrapper, "        anchors.bottomMargin: anchors.leftMargin - 2\n", "        anchors.topMargin: 0\n",
                     before=False)
    content = swap(read("modules/sidebar/Content.qml"), """            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow
""", """            radius: Tokens.rounding.large
            topLeftRadius: 0
            topRightRadius: 0
            color: Colours.tPalette.m3surfaceContainerLow
""", "sidebar card corners")
    return {"modules/sidebar/Wrapper.qml": wrapper, "modules/drawers/Panels.qml": panels,
            "modules/drawers/Interactions.qml": inter, "modules/sidebar/Content.qml": content}


def sidebar_fit():
    # The notification sidebar as tall as what's in it (its notifications, or the "all up to date" picture), at most
    # half the screen (then it scrolls, a shadow at its bottom while there's more below), not the whole height down to the utilities panel: its height to fit
    # (fitHeight), which the split windows' panels (drawers/PanelsRight.qml, PanelsLeft.qml) give it, capped
    dock = read("modules/sidebar/NotifDock.qml")
    dock = swap(dock, "    anchors.fill: parent\n    anchors.margins: Tokens.padding.medium\n", """    anchors.fill: parent
    anchors.margins: Tokens.padding.medium

    // caelestia-overlay (sidebar_fit): its height to fit, around the margins: the title, then the notifications and
    // below them room for the clear button (no longer over the last one), or the picture; both while they cross-fade
    readonly property real fitHeight: anchors.margins * 2 + title.anchors.margins + title.implicitHeight + clipRect.anchors.topMargin
        + Math.max(notifCount > 0 ? notifList.implicitHeight + ((clear.item as Item)?.implicitHeight ?? 0) + clear.anchors.margins : 0,
                   (empty.item as Item)?.implicitHeight ?? 0)
""", "notif dock size")
    dock = swap(dock, """        Loader {
            asynchronous: true
            anchors.centerIn: parent
""", """        Loader {
            id: empty

            asynchronous: true
            anchors.centerIn: parent
""", "notif dock picture")
    dock = swap(dock, """    Loader {
        asynchronous: true
        anchors.right: parent.right
        anchors.bottom: parent.bottom
""", """    Loader {
        id: clear

        asynchronous: true
        anchors.right: parent.right
        anchors.bottom: parent.bottom
""", "notif dock clear button")
    # More below than shows (it scrolls): a shadow rising from its bottom edge, gone once scrolled to the end
    dock = swap(dock, """                container: view
            }
        }
""", """                container: view
            }
        }

        // caelestia-overlay (sidebar_fit): more below, a shadow at the bottom
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitHeight: Tokens.padding.large * 4
            opacity: view.contentHeight > view.height + 1 && !view.atYEnd ? 1 : 0
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3shadow, 0)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colours.palette.m3shadow, 0.6)
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
""", "notif dock list end")
    content = swap(read("modules/sidebar/Content.qml"), """            NotifDock {
""", """            NotifDock {
                id: dock

""", "sidebar dock")
    content = insert(content, "    required property ScreenState screenState\n", """
    // caelestia-overlay (sidebar_fit)
    readonly property real fitHeight: dock.fitHeight
""", before=False)
    wrapper = insert(read("modules/sidebar/Wrapper.qml"), "    readonly property Props props: Props {}\n", """    // caelestia-overlay (sidebar_fit): its height to fit what's in it (0 until it first opens)
    readonly property real fitHeight: content.item ? (content.item as Content).fitHeight + content.anchors.topMargin + content.anchors.bottomMargin : 0
""", before=False)
    return {"modules/sidebar/NotifDock.qml": dock, "modules/sidebar/Content.qml": content,
            "modules/sidebar/Wrapper.qml": wrapper}


def sidebar_close_settled():
    # The notification sidebar closes without bouncing back. Every panel slides on Caelestia's expressive curve, which
    # overshoots its end and comes back: closing, past fully hidden and back to it. The sidebar's shape (drawn behind
    # it from its place, shown or not) hangs from the top border, so coming back it dropped a sliver into view again
    # for a moment at the end; a panel that slides to its own edge hides that. Closing on Caelestia's emphasized curve
    # instead (no overshoot), as long; opening as before
    return {"modules/sidebar/Wrapper.qml": swap(read("modules/sidebar/Wrapper.qml"), """    Behavior on offsetScale {
        Anim {}
    }
""", """    Behavior on offsetScale {
        id: offsetBehavior

        // caelestia-overlay: closing (going to 1) on a curve that doesn't overshoot, as long as opening
        Anim {
            type: offsetBehavior.targetValue > 0.5 ? Anim.Emphasized : Anim.DefaultSpatial
            duration: Tokens.anim.durations.expressiveDefaultSpatial
        }
    }
""", "sidebar offset animation")}


def sidebar_not_over_popups():
    # The notification sidebar doesn't open from its hover edge while a notification pop-up is on screen (it opened
    # under the pop-up as you went for it). Once they're gone, the edge opens it again, but not for a pointer that was
    # already resting there: it has to leave the edge and come back. Its key and Caelestia's IPC still open it; the
    # pop-ups themselves (hover, click) work as before
    inter = read("modules/drawers/Interactions.qml")
    if inter.count("showSidebarHover && !screenState.sidebar") != 2:
        raise LookupError("sidebar hover open")
    inter = inter.replace("showSidebarHover && !screenState.sidebar",
                          "root.sidebarHoverOpens(showSidebarHover) && !screenState.sidebar")
    inter = insert(inter, "    property point dragStart\n", """    // caelestia-overlay: the sidebar's hover edge held while a notification pop-up is on screen, and until the pointer
    // that was there then leaves it (sidebarHoverOpens: whether the pointer at it, or not, opens it now)
    property bool sidebarHoverHeld

    function sidebarHoverOpens(atEdge: bool): bool {
        if (!atEdge) {
            sidebarHoverHeld = false;
            return false;
        }
        if (panels.notifications.height > 0)
            sidebarHoverHeld = true;
        return !sidebarHoverHeld;
    }

""", before=False)
    # (leaving for a window, the pointer's last move this sees is still at the edge: let go there too)
    inter = insert(inter, "    onContainsMouseChanged: {\n        if (!containsMouse) {\n",
                   "            sidebarHoverHeld = false; // caelestia-overlay\n", before=False)
    # Every move, before any path that returns early or doesn't test the edge (a detached popout, fullscreen, the power
    # menu open, a button held): the pointer off the edge lets go of it there too, not only where the edge would open
    # the sidebar. The edge as Caelestia (or sidebar_from_top) tests it, so the two can't differ
    edges = re.findall(r"^ *const showSidebarHover = (.+);$", inter, re.M)
    if len(edges) != 2 or edges[0] != edges[1]:
        raise LookupError("sidebar hover edge")
    body = ""
    if "sidebarTriggerY" in edges[0]:
        trig = set(re.findall(r"^ *const sidebarTriggerY = (.+);$", inter, re.M))
        if len(trig) != 1:
            raise LookupError("sidebar hover trigger height")
        body = f"        const sidebarTriggerY = {trig.pop()};\n"
    inter = insert(inter, "    function sidebarHoverOpens(atEdge: bool): bool {\n", f"""    function atSidebarEdge(x: real, y: real): bool {{
{body}        return {edges[0]};
    }}

""")
    inter = insert(inter, "    onPositionChanged: event => {\n",
                   "        root.sidebarHoverOpens(root.atSidebarEdge(event.x, event.y)); // caelestia-overlay: let go on every path\n",
                   before=False)
    # ...and a pop-up coming up under a pointer resting on the edge (no move to see it by) holds it as well
    inter = append_block(inter, """
    // caelestia-overlay: a notification pop-up showing under a pointer resting on the sidebar's hover edge holds it
    Connections {
        function onHeightChanged() {
            if (root.containsMouse && root.panels.notifications.height > 0)
                root.sidebarHoverOpens(root.atSidebarEdge(root.mouseX, root.mouseY));
        }

        target: root.panels.notifications
    }
}
""")
    return {"modules/drawers/Interactions.qml": inter}


def launcher_fullscreen():
    # The Super menu (launcher) opens over a fullscreen game or video too (Caelestia ignores the key then), taking
    # clicks while open. shell.json's general.showOverFullscreen keeps Caelestia above fullscreen windows (Hyprland
    # doesn't move it there if that only starts as the menu opens); notifs.fullscreen and utilities.toasts.fullscreen
    # keep pop-ups off them as before
    shortcuts = first("modules/Shortcuts.qml", "daemons/Shortcuts.qml")
    sc = read(shortcuts)
    sc = swap(sc, "            if (!root.launcherInterrupted && !root.hasFullscreen) {\n",
              "            if (!root.launcherInterrupted) {\n", "launcher key")
    sc = swap(sc, '["launcher", "session", "dashboard"].includes(drawer)', '["session", "dashboard"].includes(drawer)',
              "launcher ipc")
    # Every panel's key too (dashboard, power menu, sidebar, utilities, Super+K), with the whole shell, as the Super
    # menu's; not when shell.json keeps Caelestia off fullscreen windows (opened under the game, unseen)
    sc = swap(sc, "    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false\n",
              "    readonly property bool hasFullscreen: !GlobalConfig.general.showOverFullscreen && (Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false)\n",
              "panels over fullscreen")
    sc = insert(sc, "import Caelestia\n", "import Caelestia.Config\n", before=False)
    window = read("modules/drawers/ContentWindow.qml")
    window = swap(window, "    mask: hasFullscreen ? emptyRegion : regions\n", "    mask: shellHidden ? emptyRegion : regions\n",
                  "launcher mask")
    # The whole shell (bar, border) shows while it or another panel is open, as over no fullscreen window, and hides
    # again as the last closes. Above the fullscreen window only while something of it shows there (the
    # Super menu, its opening and closing, a notification, the volume popup, a toast), else under it: an overlay above a
    # fullscreen game, even an empty one, has Hyprland redraw the whole screen every frame instead of showing the game's
    # frames alone (on a 2560x1440 300 Hz screen it took half the GPU from Overwatch)
    window = insert(window, "    property real fsTransitionProg: hasFullscreen ? 1 : 0\n",
                    "    readonly property bool shellHidden: hasFullscreen && !(screenState.launcher || screenState.dashboard || screenState.session\n"
                    "        || screenState.sidebar || screenState.utilities)\n"
                    "    onShellHiddenChanged: {\n"
                    "        if (!shellHidden)\n"
                    "            return;\n"
                    "        screenState.session = false;\n"
                    "        screenState.dashboard = false;\n"
                    "        panels.popouts.close();\n"
                    "    }\n"
                    "    readonly property bool overFullscreen: fsTransitionProg < 1 || panels.notifications.visible\n"
                    "        || panels.osd.offsetScale < 1 || panels.toasts.implicitHeight > 0\n")
    window = swap(window, "fsTransitionProg: hasFullscreen ? 1 : 0", "fsTransitionProg: shellHidden ? 1 : 0",
                  "launcher shell")
    window = swap(window, "borderLayoutThickness: hasFullscreen ? 0", "borderLayoutThickness: shellHidden ? 0",
                  "launcher border")
    window = swap(window, "WlrLayershell.layer: (fsTransitionProg > 0 && ",
                  "WlrLayershell.layer: ((hasFullscreen ? overFullscreen : fsTransitionProg > 0) && ", "launcher layer")
    if window.count("fullscreen: root.hasFullscreen\n") != 2:  # the clicks' and the bar's
        raise LookupError("launcher bar")
    window = window.replace("fullscreen: root.hasFullscreen\n", "fullscreen: root.shellHidden\n")
    return {shortcuts: sc, "modules/drawers/ContentWindow.qml": window}


def workspace_hover():
    # Each workspace in the bar lights up under the mouse like the power button (Caelestia's StateLayer: hover
    # highlight, click ripple). It takes the clicks too, doing what the shared click area over them did, except that
    # clicking the workspace you're on no longer opens a special workspace
    ws = insert(read("modules/bar/components/workspaces/Workspace.qml"), """    Component {
        id: shapeComponent
""", """    // caelestia-overlay: hover highlight and click, like the power button
    StateLayer {
        anchors.fill: undefined
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small // the indicator's size: a circle, a pill with window icons
        implicitHeight: root.LazyListView.visibleHeight // the list lays its items out by this; their height stays 0
        radius: Tokens.rounding.full
        // Clicking the workspace you're on does nothing (Caelestia opened a special workspace). (Number: a newer
        // Caelestia gives ws as text, "3", and drops Hypr.activeWsId)
        onClicked: {
            if (Hypr.focusedWorkspace?.id === Number(root.ws))
                return;
            // Both screens to their column (user/workspaces.lua), as Super+N does; Caelestia's switches only this one
            Quickshell.execDetached(["hyprctl", "eval", `dots.goto_workspace(${root.ws})`]);
        }
    }

""")
    # (here because this feature puts the file in the overlay) A window's icon before Hyprland has given its details
    # (lastIpcObject comes a moment after the window): Caelestia's threw "Value is undefined" as each window opened
    ws = swap(ws, "Icons.getAppCategoryIcon(modelData.lastIpcObject.class, ",
              'Icons.getAppCategoryIcon(modelData.lastIpcObject?.class ?? "", ', "window icon's class")
    wss = swap_block(read("modules/bar/components/workspaces/Workspaces.qml"),
                     "        MouseArea {\n            anchors.fill: workspaces\n", "", "workspaces click area",
                     must="Hypr.focusWorkspace(")
    wss = wss.replace("\n\n\n", "\n\n")
    return {"modules/bar/components/workspaces/Workspace.qml": ws,
            "modules/bar/components/workspaces/Workspaces.qml": wss}


def window_peek():
    # Window peek, like Windows' Aero Peek: resting the pointer on a live preview for a moment shows what it shows alone
    # on the desktop, the other windows out of sight, until the pointer leaves it: a window's (the dock's popout) that
    # window, a workspace's (the bar's workspace picker) every window on it. WindowPeek.qml (a service) holds what, after
    # the delay, and has the other windows on its screen fade out (dots.peek_screen, ~/.config/caelestia/user/windows.lua:
    # a tag and its rule, taken off after): the windows as Hyprland draws them over the real desktop, no focus,
    # workspace or stacking change. Windows on a workspace not being shown: every window there fades out and pictures of
    # them are drawn instead (PeekLayer.qml, in the drawers' window, under the bar and its popouts), as showing their
    # workspace would move your view
    def hover(indent, target):
        pad = " " * indent
        return (f"{pad}// caelestia-overlay: resting on it shows what it shows alone on the desktop (WindowPeek)\n"
                f"{pad}HoverHandler {{\n"
                f"{pad}    property var peeked\n\n"
                f"{pad}    onHoveredChanged: {{\n"
                f"{pad}        if (hovered) {{\n"
                f"{pad}            peeked = {target};\n"
                f"{pad}            WindowPeek.enter(peeked);\n"
                f"{pad}        }} else {{\n"
                f"{pad}            WindowPeek.exit(peeked);\n"
                f"{pad}        }}\n"
                f"{pad}    }}\n"
                f"{pad}    Component.onDestruction: if (hovered) WindowPeek.exit(peeked)\n"
                f"{pad}}}\n")

    window = insert(read("modules/drawers/ContentWindow.qml"), """    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session""", """    // caelestia-overlay: window peek's picture (PeekLayer.qml), under everything else here
    PeekLayer {
        monitor: root.monitor
    }

""")
    files = {"modules/drawers/ContentWindow.qml": window} | components("services/WindowPeek.qml", "modules/drawers/PeekLayer.qml")
    # The previews (each only where its feature put it in: the dock's popout, the workspace preview)
    menu, ws = "modules/bar/popouts/DockMenu.qml", "modules/bar/popouts/WorkspacePreview.qml"
    if not os.path.exists(os.path.join(dst, menu)) and not os.path.exists(os.path.join(dst, ws)):
        raise LookupError("no window previews (the bar dock and workspace previews are off)")
    if os.path.exists(os.path.join(dst, menu)):
        m = insert(read(menu), "            ScreencopyView {\n                id: preview\n\n", hover(16, "previewBox.modelData") + "\n",
                   before=False)
        m = insert(m, "                        captureSource: root.shows(tile.modelData) ? tile.modelData.wayland : null // qmllint disable unresolved-type\n",
                   hover(24, "tile.modelData"), before=False)
        files[menu] = m
    if os.path.exists(os.path.join(dst, ws)):
        # (on the preview as a whole: every window of that workspace shown. Over the click area too, which a handler of
        # its parent still sees hover through)
        files[ws] = insert(read(ws), "        // A click goes to the workspace\n", hover(8, "root.workspace") + "\n")
    return files


def sidebar_with_utilities():
    # Super+K (Caelestia's "show all": the launcher, dashboard, volume slider and utilities panel) opens the notification
    # sidebar too, with the utilities panel joined under it (sidebar_shape). The launcher closing (Esc) closes them all
    # unless hovered: Caelestia's left the utilities panel open until the pointer moved
    shortcuts = first("modules/Shortcuts.qml", "daemons/Shortcuts.qml")
    sc = swap(read(shortcuts), "v.utilities = !(", "v.utilities = v.sidebar = !(", "show all")
    sc = swap(sc, "|| v.utilities);", "|| v.utilities || v.sidebar);", "show all")
    # A "shortcut mode" for the sidebar, as Caelestia has for the dashboard: opened while the mouse isn't on it, hovering
    # elsewhere doesn't close it (with showOnHover any move off it would) until the mouse goes onto it or the launcher closes
    inter = read("modules/drawers/Interactions.qml")
    on_sidebar = """        function onSidebarChanged() {
            // Not when the hover trigger (the top edge over it) opened it: it's still above the screen then
            const border = root.Config.border; // through root: a Connections has no screen to read the settings for
            const inTrigger = root.mouseY < Math.max(border.minThickness, border.thickness) + border.rounding
                && root.withinPanelWidth(root.panels.sidebar, root.mouseX, root.mouseY);
            if (root.screenState.sidebar)
                root.sidebarShortcutActive = !inTrigger && !root.inRightPanel(root.panels.sidebar, root.mouseX, root.mouseY);
            else
                root.sidebarShortcutActive = false;
        }
"""
    # A newer Caelestia has this mode itself: only its onSidebarChanged swapped for this one (its own counts a sidebar
    # the hover trigger opened as shortcut-opened, so moving away no longer closed it)
    if "    property bool sidebarShortcutActive\n" in inter:
        inter = swap_block(inter, "        function onSidebarChanged() {", on_sidebar, "sidebar onSidebarChanged",
                           must="sidebarShortcutActive")
        # (and as below: back to hover control once the pointer is on it, not only in its hover trigger, which the
        # edge-only trigger (edge_triggers) made its last few pixels; the launcher closing closes it and the utilities
        # panel unless they're hovered)
        inter = swap(inter, "                } else if (showSidebarHover) {\n",
                     "                } else if (showSidebarHover || inRightPanel(panels.sidebar, x, y)) {\n",
                     "sidebar hovered: back to hover control")
        inter = insert(inter, "                root.sidebarShortcutActive = false;\n\n", """                if (!root.inRightPanel(root.panels.sidebar, root.mouseX, root.mouseY))
                    root.screenState.sidebar = false;
                if (!root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY))
                    root.screenState.utilities = false;

""")
        return {shortcuts: sc, "modules/drawers/Interactions.qml": inter}
    inter = insert(inter, "    property bool utilitiesShortcutActive\n", "    property bool sidebarShortcutActive\n", before=False)
    inter = swap(inter, "            if (Config.sidebar.showOnHover)\n                screenState.sidebar = false;\n",
                 "            if (Config.sidebar.showOnHover && !sidebarShortcutActive)\n                screenState.sidebar = false;\n",
                 "sidebar closes on leaving")
    inter = swap(inter, "                    if (!inSidebarArea)\n                        screenState.sidebar = false;\n",
                 "                    if (inSidebarArea)\n                        sidebarShortcutActive = false; // hovered: back to hover control\n"
                 "                    else if (!sidebarShortcutActive)\n                        screenState.sidebar = false;\n",
                 "sidebar closes off it")
    inter = insert(inter, "                root.utilitiesShortcutActive = false;\n\n", """                root.sidebarShortcutActive = false;
                if (!root.inRightPanel(root.panels.sidebar, root.mouseX, root.mouseY))
                    root.screenState.sidebar = false;
                if (!root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY))
                    root.screenState.utilities = false;

""")
    inter = insert(inter, "        function onUtilitiesChanged() {\n", on_sidebar + "\n")
    return {shortcuts: sc, "modules/drawers/Interactions.qml": inter}


def bar_menu():
    # Right-clicking the empty bar space between the workspaces and the tray (not on the dock) opens a small menu in its
    # popout style (BarMenu.qml): Task Manager (btop) and the floating/tiling switch. It stays while the mouse moves near it (hovering the
    # bar would close it, there being nothing under the mouse to show): it closes 60 px up or down the bar, on leaving
    # it, on an action, another click on the bar, or a click outside Caelestia (the focus grab)
    content = insert(read("modules/bar/popouts/Content.qml"), '        Popout {\n            name: "bluetooth"', '''        Popout {
            name: "barmenu"
            sourceComponent: BarMenu {
                popouts: root.popouts
            }
        }

''')
    bar = insert(read("modules/bar/Bar.qml"), "    function checkPopout(y: real): void {\n", """    // caelestia-overlay: the right-click menu, by the click, only in the empty space between the workspaces and the
    // tray, minus the dock (one stretch without a dock, the gaps above and below it with one)
    function openMenu(y: real): void {
        const entries = Array.from({length: repeater.count}, (_, i) => repeater.itemAt(i) as EntryWrapper);
        const ws = entries.find(e => e?.entryId === "workspaces");
        const tray = entries.find(e => e?.entryId === "tray");
        const dock = entries.find(e => e?.entryId === "dock")?.item;
        if (y < (ws ? ws.y + ws.height : 0) || y > (tray ? tray.y : height))
            return;
        const dockTop = dock?.mapToItem(root, 0, 0).y;
        if (dock && y >= dockTop && y <= dockTop + dock.height)
            return;
        popouts.currentName = "barmenu";
        popouts.currentCenter = y;
        popouts.hasCurrent = true;
    }

""")
    bar = insert(bar, "    function checkPopout(y: real): void {\n", """        if (popouts.hasCurrent && popouts.currentName === "barmenu" && Math.abs(y - popouts.currentCenter) < 60)
            return; // caelestia-overlay: the menu stays while the mouse is near where it was opened
""", before=False)
    wrapper = insert(read("modules/bar/BarWrapper.qml"), "    function closeTray(): void {\n", """    function openMenu(y: real): void {
        (content.item as Bar)?.openMenu(y);
    }

""")
    # Right after the press is noted: in its own block when tray_click (which makes one) is off
    menu = """        // caelestia-overlay: a right-click on the bar opens its menu (again, where clicked), any other click closes it
        if (popouts.currentName === "barmenu")
            popouts.hasCurrent = false;
        if (event.button === Qt.RightButton && event.x < bar.implicitWidth)
            bar.openMenu(event.y);
"""
    inter = read("modules/drawers/Interactions.qml")
    one_line = "    onPressed: event => dragStart = Qt.point(event.x, event.y)\n"
    if one_line in inter:
        inter = swap(inter, one_line, "    onPressed: event => {\n        dragStart = Qt.point(event.x, event.y);\n" + menu + "    }\n",
                     "onPressed")
    else:
        inter = insert(inter, "        dragStart = Qt.point(event.x, event.y);\n", menu, before=False)
    window = insert(read("modules/drawers/ContentWindow.qml"), '            if (panels.popouts.currentName.startsWith("traymenu")', """            if (panels.popouts.hasCurrent && panels.popouts.currentName === "barmenu")
                return true; // caelestia-overlay: a click outside Caelestia closes the bar's menu
""")
    files = {"modules/bar/popouts/Content.qml": content, "modules/bar/Bar.qml": bar, "modules/bar/BarWrapper.qml": wrapper,
             "modules/drawers/Interactions.qml": inter, "modules/drawers/ContentWindow.qml": window}
    return files | components("modules/bar/popouts/BarMenu.qml")


def dashboard_language():
    # The dashboard's calendar and weather tab in the system language (LANG), not the date format's (LC_TIME, which
    # Qt.locale() follows), and the weather tab's heading with a 3-letter weekday like the rest. Kept on main: its Tr.locale
    # is LC_TIME's too for a LANG it has no translation for (en_GB)
    lang = 'Qt.locale((Quickshell.env("LANG") ?? "").split(".")[0])'
    imp = "import QtQuick.Layouts\n"
    cal = insert(read("modules/dashboard/dash/Calendar.qml"), imp, "import Quickshell\n", before=False)
    cal = swap_one_of(cal, ("                locale: Qt.locale()\n", "                locale: Tr.locale\n"),
                      lambda old: f"                locale: {lang}\n", "MonthGrid locale")
    weather = insert(read("modules/dashboard/WeatherTab.qml"), imp, "import Quickshell\n", before=False)
    weather = swap_one_of(weather, ('new Date().toLocaleDateString(Qt.locale(), "dddd, MMMM d")',
                                    'Tr.formatDateTime(new Date(), "dddd, MMMM d")'),
                          lambda old: f'new Date().toLocaleDateString({lang}, "ddd, MMMM d")', "weather heading date")
    day = "new Date(forecastItem.modelData.date)"
    for fmt, what in (("ddd", "forecast weekday"), ("MMM d", "forecast date")):
        weather = swap_one_of(weather, (f'{day}.toLocaleDateString(Qt.locale(), "{fmt}")', f'Tr.formatDateTime({day}, "{fmt}")'),
                              lambda old, fmt=fmt: f'{day}.toLocaleDateString({lang}, "{fmt}")', what)
    return {"modules/dashboard/dash/Calendar.qml": cal, "modules/dashboard/WeatherTab.qml": weather}


def lock_intro():
    # The lock screen comes in like the login screen, macOS-like: the password field comes down onto the screen from in
    # front of it (bigger and out of focus, as if close to you, shrinking and sharpening into place, slowing
    # gradually), then the rest in turn from the centre outward, instead of Caelestia's lock badge opening into the
    # card. Unlocking is Caelestia's as before (the card shrinks back into the badge). The motion is the login screen's
    # (caelestia-greeter/shell.qml): change both together
    surface = read("modules/lock/LockSurface.qml")
    surface = swap_block(surface, "    ParallelAnimation {\n        id: initAnim\n", """    // caelestia-overlay: element n moves while intro goes from n * 0.25 to n * 0.25 + 1 (introT: its own 0 to 1)
    property real intro: 0

    function introT(n: int): real {
        return Math.max(0, Math.min(1, intro - n * 0.25));
    }

    // No fade: it shows the moment its turn starts, fully blurred
    function fallOpacity(n: int): real {
        return introT(n) > 0 ? 1 : 0;
    }

    // Out of focus while close to you, sharpening as it comes down
    function fallBlur(n: int): real {
        return Math.pow(1 - introT(n), 3);
    }

    // From 220% down to its size: fast at first, slowing gradually all the way into place
    function fallScale(n: int): real {
        return 1 + 1.2 * Math.pow(1 - introT(n), 3);
    }

    ParallelAnimation {
        id: initAnim

        running: true

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        NumberAnimation {
            target: root
            property: "intro"
            to: 4 * 0.25 + 1
            duration: 500
        }
    }
""", "lock init animation", must="lockContent")
    # The card at its full size from the start, its background coming in with the password field; the badge's icon
    # hidden, upright for the unlock, which brings it back
    surface = swap(surface, "        implicitWidth: size\n",
                   "        implicitWidth: (root.screen?.height ?? 0) * Tokens.sizes.lock.heightMult * Tokens.sizes.lock.ratio\n",
                   "lock card start")
    surface = swap(surface, "        implicitHeight: size\n",
                   "        implicitHeight: (root.screen?.height ?? 0) * Tokens.sizes.lock.heightMult\n", "lock card start")
    for line in ("rotation: 180", "scale: 0"):
        surface = drop_after(surface, "        visible: Config.lock.enabled\n", line, "lock card start")
    surface = swap(surface, "            radius: parent.radius\n",
                   "            radius: lockContent.Tokens.rounding.extraLarge * 1.5\n", "lock card background")
    surface = swap(surface, "            opacity: Colours.transparency.enabled ? Colours.transparency.base : 1\n",
                   "            opacity: (Colours.transparency.enabled ? Colours.transparency.base : 1) * root.fallOpacity(0)\n"
                   "            scale: root.fallScale(0)\n", "lock card background")
    surface = insert(surface, "                shadowEnabled: true\n",
                     "                blurEnabled: true\n                blur: root.fallBlur(0)\n")
    icon = "            fontStyle: Tokens.font.icon.builders.extraLarge"
    surface = drop_after(surface, icon, "rotation: 180", "lock badge icon")
    surface = insert(surface, icon, "            opacity: 0\n")
    for line in ("opacity: 0", "scale: 0"):
        surface = drop_after(surface, "            lock: root\n", line, "lock content start")

    def falls(n):
        # one element's entrance, blurred through a layer while it comes in (no layer once in place)
        return (f"        opacity: root.lock.fallOpacity({n})\n        scale: root.lock.fallScale({n})\n"
                f"        layer.enabled: root.lock.introT({n}) < 1\n"
                f"        layer.effect: MultiEffect {{ blurEnabled: true; blur: root.lock.fallBlur({n}); blurMax: 48 }}\n")

    center = insert(read("modules/lock/Center.qml"), "import QtQuick\n", "import QtQuick.Effects\n", before=False)
    for anchor, n in (("    Clock {\n", 3), ("    StyledText {\n", 2), ("    ProfilePic {\n", 1),
                      ("    PasswordInput {\n", 0), ("    StateMessage {\n", 1)):
        center = insert(center, anchor, falls(n), before=False)
    content = insert(read("modules/lock/Content.qml"), "import QtQuick\n", "import QtQuick.Effects\n", before=False)
    for first in ("WeatherInfo", "Resources"):
        content = swap(content, f"""    ColumnLayout {{
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        {first} {{
""", f"""    ColumnLayout {{
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium
{falls(4)}
        {first} {{
""", f"lock {first} column")
    return {"modules/lock/LockSurface.qml": surface, "modules/lock/Center.qml": center, "modules/lock/Content.qml": content}


def battery_suspend():
    # A critical battery hibernates where the system can, else suspends: an AgrOS install has no swap to hibernate into
    # (zram only), and there Caelestia's hibernate call did nothing after its "Hibernating in 5 seconds" (a toast) and
    # the laptop died; a system with swap to resume from (CachyOS installed before, its own swap) still hibernates, as
    # suspending there drains the battery for good. systemctl's hibernate fails at once where logind says it can't
    # (CanHibernate). The session menu's Hibernate button the same, unless set to something else in shell.json (here:
    # it reaches existing accounts, not only new ones)
    sleep = '["sh", "-c", "systemctl hibernate || systemctl suspend"]'
    rel = first("modules/BatteryMonitor.qml", "daemons/BatteryMonitor.qml")  # (main moved it)
    s = swap(read(rel), "onTriggered: SessionManager.hibernate()", f"onTriggered: Quickshell.execDetached({sleep})",
             "the hibernate call")
    if not re.search(r"^import Quickshell$", s, re.M):
        raise LookupError(f"{rel}'s Quickshell import")
    s = swap(s, 'Toaster.toast(Tr.tr("Hibernating in 5 seconds"), Tr.tr("Hibernating to prevent data loss")',
             'Toaster.toast(Tr.tr("Going to sleep in 5 seconds"), Tr.tr("Hibernating, or suspending where it can\'t, to prevent data loss")',
             "the toast")
    menu = "modules/session/Content.qml"
    # (a command that isn't one of its SessionManager's own: the button runs it as it is)
    m = swap(read(menu), "        command: Config.session.commands.hibernate\n",
             f'        command: String(Config.session.commands.hibernate) === "hibernate" ? {sleep} : Config.session.commands.hibernate\n',
             "the session menu's hibernate button")
    # Its icon a moon, as the login screen's sleep button (Caelestia's "downloading", an arrow into a circle, read as a
    # download), unless set to something else in shell.json; a line moon, as the lock and login screens' (the menu's
    # buttons draw their icons filled)
    m = swap(m, "        icon: Config.session.icons.hibernate\n",
             '        icon: String(Config.session.icons.hibernate) === "downloading" ? "bedtime" : Config.session.icons.hibernate\n'
             '        label.fill: icon === "bedtime" ? 0 : 1\n',
             "the session menu's hibernate icon")
    if "Quickshell.execDetached(command)" not in m:
        raise LookupError(f"{menu}: its buttons don't run a command of their own")
    return {rel: s, menu: m}


def power_menu():
    """The power menu top to bottom Log out, Sleep, (its picture,) Restart, Shut down; Shut down in the menu's own
    colour, the others alike (the focused one, Log out as it opens, took that colour: it read as Log out's own; the focus
    is still its rounder shape), and on Restart and Shut down a mark while an update the boot downloaded waits to install
    as they run (auto-update's /var/lib/auto-update/ready, how many: its firmware's list too)"""
    menu = "modules/session/Content.qml"
    m = read(menu)
    head = "    SessionButton {\n        id: logout\n"
    tail = "    component SessionButton: IconButton {\n"
    if m.count(head) != 1 or m.count(tail) != 1:
        raise LookupError("the session menu's buttons")
    a, b = m.index(head), m.index(tail)
    # (its buttons and picture, each a block of the Column's: by its id, the picture by its type)
    blocks, cur = {}, []
    for line in m[a:b].splitlines(True):
        cur.append(line)
        if line == "    }\n":
            text = "".join(cur).strip("\n") + "\n"
            ident = re.search(r"^        id: (\w+)$", text, re.M)
            key = ident.group(1) if ident else ("gif" if text.startswith("    AnimatedImage {") else None)
            if key is None or key in blocks:
                raise LookupError(f"the session menu's blocks: {text.splitlines()[0]}")
            blocks[key] = text
            cur = []
    if set(blocks) != {"logout", "shutdown", "hibernate", "reboot", "gif"} or "".join(cur).strip():
        raise LookupError(f"the session menu's buttons: {sorted(blocks)}")
    order = [("logout", None, "hibernate", ""), ("hibernate", "logout", "reboot", ""),
             ("reboot", "hibernate", "shutdown", "        updates: root.updateReady\n"),
             ("shutdown", "reboot", None, "        accent: true\n        updates: root.updateReady\n")]
    out = []
    for key, up, down, extra in order:
        text = re.sub(r"^        KeyNavigation\.(up|down): \w+\n", "", blocks[key], flags=re.M)
        nav = (f"        KeyNavigation.up: {up}\n" if up else "") + (f"        KeyNavigation.down: {down}\n" if down else "")
        text = text.replace("\n\n    }\n", "\n    }\n")
        text = text[:-len("    }\n")].rstrip("\n") + "\n" + extra + ("\n" + nav if nav else "") + "    }\n"
        out.append(text)
        if key == "hibernate":
            out.append(blocks["gif"])
    m = m[:a] + "\n".join(out) + "\n" + m[b:]
    m = swap(m, """        inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
""", """        // caelestia-overlay: the menu's own colour Shut down's alone, not the focused one's
        inactiveColour: accent ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: accent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
""", "the session buttons' colours")
    m = swap(m, "        required property list<string> command\n", """        required property list<string> command
        // caelestia-overlay: the menu's own colour (Shut down's), and the mark of an update installing as it runs
        property bool accent
        property bool updates

        // (with an update waiting, its top right corner turned inside out: an inverted curve of the same radius, from
        // where the corner's own curve starts, its two ends themselves rounded, and the update's mark in that space,
        // filled like the icons. Its colour and its hover and press layer have that outline; its icon doesn't change)
        readonly property color fillColour: disabled ? disabledColour : internalChecked ? activeColour : inactiveColour

        color: updates ? "transparent" : fillColour
        stateLayer.layer.enabled: updates
        stateLayer.layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: notchMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        NotchShape {
            anchors.fill: parent
            z: -1
            visible: button.updates
            fill: button.fillColour
            cornerRadius: button.radius
        }

        NotchShape {
            id: notchMask

            anchors.fill: parent
            visible: false
            layer.enabled: true
            fill: "white"
            cornerRadius: button.radius
        }

        MaterialIcon {
            visible: button.updates
            x: button.width - button.radius * 0.4 - width / 2
            y: button.radius * 0.4 - height / 2
            scale: button.radius * 0.72 / Math.max(1, implicitHeight)
            text: "download"
            color: Colours.palette.m3onSurface
            fill: 1
            fontStyle: Tokens.font.icon.builders.large.build()
        }
""", "the session buttons' update notch")
    m = swap(m, "    spacing: Tokens.spacing.large\n", """    spacing: Tokens.spacing.large

    // caelestia-overlay: an update the boot downloaded waits to install at the next restart or shut down (auto-update's
    // count, or its firmware's list): looked at again every half minute (the file comes only once the download's done)
    property bool updateReady: packagesReady || firmwareReady
    property bool packagesReady
    property bool firmwareReady

    FileView {
        id: readyFile

        path: "/var/lib/auto-update/ready"
        printErrors: false
        onLoaded: root.packagesReady = parseInt(text()) > 0
        onLoadFailed: root.packagesReady = false
    }

    FileView {
        id: firmwareFile

        path: "/var/lib/auto-update/firmware"
        printErrors: false
        onLoaded: root.firmwareReady = text().trim() !== ""
        onLoadFailed: root.firmwareReady = false
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: {
            readyFile.reload();
            firmwareFile.reload();
        }
    }
""", "the session menu's update state")
    m = insert(m, "import Quickshell\n", "import Quickshell.Io\n", before=False)
    m = insert(m, "import QtQuick\n", "import QtQuick.Effects\nimport QtQuick.Shapes\n", before=False)
    m = insert(m, "    component SessionButton: IconButton {\n", """    // A button's outline with its top right corner turned inside out (SessionButton's, with an update waiting): the
    // other three corners round (cornerRadius), that one an inverted curve of the same radius centred on the corner,
    // and its two ends rounded too (fillet), each meeting the edge it starts from
    component NotchShape: Shape {
        id: notch

        property color fill
        property real cornerRadius
        readonly property real fillet: cornerRadius / 4
        // (each end's round: how far along its edge it starts, and where it meets the inverted curve)
        readonly property real along: Math.sqrt(cornerRadius * cornerRadius + 2 * cornerRadius * fillet)
        readonly property real k: cornerRadius / Math.max(0.001, cornerRadius + fillet)

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: notch.fill
            strokeColor: "transparent"
            startX: notch.cornerRadius
            startY: 0

            PathLine { x: notch.width - notch.along; y: 0 }
            PathArc { x: notch.width - notch.along * notch.k; y: notch.fillet * notch.k; radiusX: notch.fillet; radiusY: notch.fillet }
            PathArc { x: notch.width - notch.fillet * notch.k; y: notch.along * notch.k; radiusX: notch.cornerRadius; radiusY: notch.cornerRadius; direction: PathArc.Counterclockwise }
            PathArc { x: notch.width; y: notch.along; radiusX: notch.fillet; radiusY: notch.fillet }
            PathLine { x: notch.width; y: notch.height - notch.cornerRadius }
            PathArc { x: notch.width - notch.cornerRadius; y: notch.height; radiusX: notch.cornerRadius; radiusY: notch.cornerRadius }
            PathLine { x: notch.cornerRadius; y: notch.height }
            PathArc { x: 0; y: notch.height - notch.cornerRadius; radiusX: notch.cornerRadius; radiusY: notch.cornerRadius }
            PathLine { x: 0; y: notch.cornerRadius }
            PathArc { x: notch.cornerRadius; y: 0; radiusX: notch.cornerRadius; radiusY: notch.cornerRadius }
        }
    }

""")
    return {menu: m}


def osd_quiet_start():
    # No volume popup unless you changed the volume: not when the shell starts (login, caelestia-restart; changes in
    # its first 3 s are ignored), and not when the sound device changes or comes up: at login the sound system can
    # start after the shell, its output appearing then (and a headset connecting later) counted as a volume change
    rel = "modules/osd/Wrapper.qml"
    s = swap(read(rel), """    function show(): void {
        screenState.osd = true;""", """    property bool started
    // Bound, so a device change is seen when it happens (the volume may not change with it: same level on both)
    readonly property string devices: `${Audio.sink?.id}:${Audio.sink?.ready}:${Audio.source?.id}:${Audio.source?.ready}`

    onDevicesChanged: {
        seen = devices; // noted here too: with no volume change after it, the next real press would count as the change
        quiet.restart();
    }

    Timer {
        running: true
        interval: 3000
        onTriggered: {
            root.seen = root.devices;
            root.started = true;
        }
    }

    // The volume "changes" that come with a device change, right after it
    Timer {
        id: quiet

        interval: 500
    }

    // The devices the last volume change came with (set, not bound): the volume can change before onDevicesChanged
    property string seen

    function show(): void {
        if (devices !== seen) {
            seen = devices;
            quiet.restart();
        }
        if (!started || quiet.running)
            return;
        screenState.osd = true;""", "osd show()")
    # ...nor when the screen's brightness is first read: over DDC (an external screen) that takes several seconds, past
    # the 3 s above, and the 0 it starts at "changing" to the real level showed the popup at every start
    # (its body alone, not its head: internal_brightness puts a line before it)
    s = swap(s, """            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }
""", """            if (root.brightnessRead)
                root.show();
            root.brightnessRead = true;
            root.brightness = root.monitor?.brightness ?? 0;
        }

        // Read again over DDC once the screen's DDC bus is found (after a first read through the backlight)
        function onBusNumChanged(): void {
            root.brightnessRead = false;
            ddcRead.restart();
        }
""", "osd brightness")
    s = swap(s, "    property bool started\n", """    property bool started
    // The screen's brightness has been read once (a changed screen is read again)
    property bool brightnessRead
    onMonitorChanged: brightnessRead = false
    // The DDC read can bring the value already shown (no change to see): counted as read once it's had time (~5 s)
    Timer {
        id: ddcRead

        interval: 10000
        onTriggered: root.brightnessRead = true
    }
""", "osd started")
    return {rel: s}


def face_quiet():
    # The account picture (~/.face) only asked for once it's there: Caelestia warned "Source file does not exist" each
    # time the dashboard or lock screen showed without one. Looked for when they're made and after picking one
    check = """    // caelestia-overlay: ~/.face only once it's there (face_quiet)
    property bool hasFace

    Process {
        id: faceCheck

        running: true
        command: ["test", "-e", `${Paths.home}/.face`]
        onExited: code => root.hasFace = code === 0
    }

"""
    faces = ("path: `${Paths.home}/.face`", "source: `${Paths.home}/.face`")
    files = {}
    for rel, anchor in (("modules/dashboard/dash/User.qml", "    property color pfpFallbackColour"),
                        ("modules/lock/center/ProfilePic.qml", "    implicitWidth: Math.round(centerWidth * 0.7)")):
        s = insert(read(rel), "import QtQuick\n", "import Quickshell.Io\n", before=False)
        s = insert(s, anchor, check)
        files[rel] = swap_one_of(s, faces, lambda old: old.replace("`${Paths.home}/.face`", 'root.hasFace ? `${Paths.home}/.face` : ""'),
                                 f"{rel} picture")
    files["modules/dashboard/dash/User.qml"] = insert(files["modules/dashboard/dash/User.qml"], check, """    Connections {
        target: root.facePicker

        function onAccepted(): void {
            faceCheck.running = true; // after the dashboard's own handler has copied it
        }
    }

""", before=False)
    return files


def lock_power():
    # Sleep, restart and power off on the lock screen, bottom right like the login screen's (caelestia-greeter/shell.qml):
    # round buttons over the dimmed wallpaper, fading in and out with the lock's content. Kept on main: its
    # lock.enableSessionControls shows logout/shutdown/hibernate/reboot only while hovering the resources card
    rel = "modules/lock/LockSurface.qml"
    s = read(rel)
    s = insert(s, "import QtQuick\n", "import QtQuick.Layouts\nimport Quickshell\n", before=False)
    s = append_block(s, """
    // caelestia-overlay: power buttons
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.extraLargeIncreased
        spacing: Tokens.spacing.medium
        opacity: content.opacity
        visible: Config.lock.enabled

        Repeater {
            model: [["bedtime", "suspend"], ["restart_alt", "reboot"], ["power_settings_new", "poweroff"]]

            StyledRect {
                id: powerBtn

                required property var modelData

                implicitWidth: 52
                implicitHeight: 52
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.82)

                StateLayer {
                    radius: parent.radius
                    onClicked: Quickshell.execDetached(["systemctl", powerBtn.modelData[1]])
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: powerBtn.modelData[0]
                    fill: 0 // (line icons: the sleep moon as the power menu's and the login screen's)
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.builders.large.build()
                }
            }
        }
    }
}
""")
    return {rel: s}


def clock_digits():
    # Bar clock: the hour above the minutes digit by digit ("21" over "22": the 2s one above the other). Caelestia
    # stretches each line to the same width through the font's width axis, and the font's same-width digits (tnum)
    # draw a wider 1. Instead each digit, as drawn normally, sits centred in a slot as wide as the widest digit
    rel = "modules/bar/components/Clock.qml"
    s = swap_block(read(rel), "    function fontFor(", """    function fontFor(text: string, metricWidth: int): font {
        return root.font.build();
    }

    // caelestia-overlay: the digits' slots (Digits below)
    FontMetrics {
        id: digitMetrics

        font: root.font.build()
    }
    // (reading the font first: the binding then follows a font change, which advanceWidth() alone doesn't tell it)
    readonly property real digitWidth: (digitMetrics.font, Math.max(...[..."0123456789"].map(c => digitMetrics.advanceWidth(c))))

    component Digits: Row {
        id: digits

        property string text

        Repeater {
            model: digits.text.split("")

            StyledText {
                required property string modelData

                width: root.digitWidth
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                font: root.font.build()
                color: root.colour
            }
        }
    }
""", "clock font")
    for what, extra in (("hour", ""), ("minute", "            Layout.topMargin: -parent.spacing - 4\n")):
        head = f"            text: Time.{what}Str\n            font: root.fontFor("
        # The line's StyledText (from its first line, found by its text) becomes Digits
        i = s.index(head) if s.count(head) == 1 else -1
        block_start = s.rfind("        StyledText {\n", 0, i) if i >= 0 else -1
        if block_start < 0 or s[block_start:i].count("\n") > 3:
            raise LookupError(f"clock {what}")
        s = swap_block(s[:block_start] + "@@" + s[block_start + 8:], "@@StyledText {\n", f"""        Digits {{
{extra}            Layout.alignment: Qt.AlignHCenter
            text: Time.{what}Str
        }}
""", f"clock {what}", must=f"Time.{what}Str")
    # The seconds (when shown) the same way
    s = swap_block(s, "            sourceComponent: StyledText {\n                text: Time.format(\"ss\")\n",
                   """            sourceComponent: Digits {
                text: Time.format("ss")
            }
""", "clock seconds")
    return {rel: s}


def clock_calendar():
    # Hovering the bar's clock shows the month's calendar in a popout (ClockCalendar.qml: the dashboard's calendar), as
    # on Windows; the workspace previews' popout pattern (Bar.qml picks, Content.qml shows it)
    content = insert(read("modules/bar/popouts/Content.qml"), '        Popout {\n            name: "bluetooth"', '''        Popout {
            name: "calendar"
            sourceComponent: ClockCalendar {}
        }

''')
    bar = insert(read("modules/bar/Bar.qml"), '        } else if (id === "activeWindow"', """        } else if (id === "clock") {
            // caelestia-overlay: the month's calendar (ClockCalendar.qml)
            popouts.currentName = "calendar";
            popouts.currentCenter = (ch.item as Item).mapToItem(root, 0, (ch.item as Item).implicitHeight / 2).y ?? 0;
            popouts.hasCurrent = true;
""")
    return {"modules/bar/popouts/Content.qml": content, "modules/bar/Bar.qml": bar,
            **components("modules/bar/popouts/ClockCalendar.qml")}


def workspace_preview():
    # Hovering a workspace on the bar shows a preview of it in a popout (WorkspacePreview.qml): its windows, live, where
    # they are on its screen. Only workspaces with windows; the dock's popout pattern (Bar.qml picks, PopoutState
    # carries which, Content.qml shows it)
    state = insert(read("modules/bar/popouts/PopoutState.qml"), "    property bool hasCurrent\n",
                   "    property int previewWs // caelestia-overlay: the workspace the preview popout shows\n", before=False)
    wrapper = insert(read("modules/bar/popouts/Wrapper.qml"), "    property alias hasCurrent: popoutState.hasCurrent\n",
                     "    property alias previewWs: popoutState.previewWs\n", before=False)
    content = insert(read("modules/bar/popouts/Content.qml"), '        Popout {\n            name: "bluetooth"', '''        Popout {
            name: "wspreview"
            sourceComponent: WorkspacePreview {
                popouts: root.popouts
            }
        }

''')
    bar = insert(read("modules/bar/Bar.qml"), '        } else if (id === "activeWindow"', """        } else if (id === "workspaces") {
            // caelestia-overlay: the hovered workspace's preview, if it has windows
            // The one whose top is the nearest above the mouse (the list's items report no height)
            const wsItem = ((ch.item as Item)?.workspaces ?? []).filter(w => w && root.mapToItem(w, 0, y).y >= 0) // qmllint disable missing-property
                .sort((a, b) => root.mapToItem(a, 0, y).y - root.mapToItem(b, 0, y).y)[0];
            if (wsItem && Hypr.workspaces.values.some(w => w.id === Number(wsItem.ws) && w.toplevels.values.some(t => t.lastIpcObject?.mapped))) {
                popouts.previewWs = wsItem.ws;
                popouts.currentName = "wspreview";
                popouts.currentCenter = y;
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
""")
    return {"modules/bar/popouts/PopoutState.qml": state, "modules/bar/popouts/Wrapper.qml": wrapper,
            "modules/bar/popouts/Content.qml": content, "modules/bar/Bar.qml": bar,
            **components("modules/bar/popouts/WorkspacePreview.qml")}


def snap_preview():
    # Where a dragged window snaps if let go now (AgrOS's window snapping: ~/.config/caelestia/user/windows.lua), drawn
    # as on Windows: SnapPreview.qml in the drawers' window, told by WindowDrag.qml (Hyprland's custom events)
    window = insert(read("modules/drawers/ContentWindow.qml"), """    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session""", """    // caelestia-overlay: where a dragged window snaps (SnapPreview.qml)
    SnapPreview {
        monitor: root.monitor
    }

""")
    return {"modules/drawers/ContentWindow.qml": window} | components("services/WindowDrag.qml", "modules/drawers/SnapPreview.qml")


def top_edge_one_panel():
    # The top edge opens one panel at a time: the notification sidebar (sliding down from the top: sidebar_from_top)
    # along its own span, the dashboard along the rest of its width, and neither while the other is open. On a narrow
    # screen (one standing on its side) the dashboard is as wide as the screen and covered the sidebar's span: one touch
    # of the top edge opened both, one over the other
    rel = "modules/drawers/Interactions.qml"
    inter = read(rel)
    dash = re.findall(r"^ *const showDashboard = (.+);$", inter, re.M)
    if len(dash) != 1:
        raise LookupError("the dashboard's hover")
    inter = inter.replace(f"const showDashboard = {dash[0]};", f"const showDashboard = {dash[0]}"
                          " && (screenState.dashboard || !screenState.sidebar && !withinPanelWidth(panels.sidebar, x, y)); // caelestia-overlay: not over the sidebar's span")
    opens = re.findall(r"if \((.*showSidebarHover\)?) && !screenState\.sidebar\)", inter)
    if len(opens) != 2:
        raise LookupError("the sidebar's hover")
    for o in set(opens):
        inter = inter.replace(f"if ({o} && !screenState.sidebar)", f"if ({o} && !screenState.sidebar && !screenState.dashboard)")
    return {rel: inter}


def edge_triggers():
    # The panels that open on hover (dashboard, Super menu, notification sidebar, volume, utilities) open only from the
    # screen's very edge (its last few pixels, edgePx), not the border's whole width (on an empty workspace, a band 80 px
    # deep); not while a mouse button is held or a window is being dragged (WindowDrag.qml: a window dragged to the top
    # to maximise it opened the dashboard). Once open, one stays open while the pointer is over it, as before. On a side
    # with another screen beyond (sideShared), the old band: there the pointer goes on across, the edge hard to stop on.
    # The bar's popouts on hover (the dock's, a workspace's preview...) not while a window is dragged over the bar either
    # (one dragged to the left edge to snap it opened the dock's popout, still open after it was let go): the bar then
    # as if the pointer were off it, an open popout closed
    inter = read("modules/drawers/Interactions.qml")
    # (WindowDrag is a service: Caelestia's Interactions imports none, and without this every hover failed)
    if not re.search(r"^import qs\.services$", inter, re.M):
        inter = insert(inter, "import qs.components\n", "import qs.services\n", before=False)
    inter = insert(inter, "    property bool utilitiesShortcutActive\n", """
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
""", before=False)
    inter = swap(inter, "const showDashboard = Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);",
                 "const showDashboard = Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y) && root.edgeHover(screenState.dashboard, y < root.edgePx || root.sideShared(\"top\"));",
                 "the dashboard's hover")
    inter = swap(inter, "const showUtilities = inBottomPanel(panels.utilities, x, y, true);",
                 "const showUtilities = inBottomPanel(panels.utilities, x, y, true) && root.edgeHover(screenState.utilities, y >= height - root.edgePx || root.sideShared(\"bottom\"));",
                 "the utilities' hover")
    inter = swap(inter, "if (!screenState.launcher && inBottomPanel(panels.launcher, x, y))",
                 "if (!screenState.launcher && inBottomPanel(panels.launcher, x, y) && root.edgeHover(false, y >= height - root.edgePx || root.sideShared(\"bottom\")))",
                 "the Super menu's hover")
    # (the volume's, over a fullscreen window too)
    inter = swap(inter, "root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);",
                 "root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y) && root.edgeHover(root.panels.osd.hovered, x >= width - root.edgePx || root.sideShared(\"right\"));",
                 "the volume's hover over a fullscreen window")
    osd = "inRightPanel(panels.osdWrapper, x, y);"
    if inter.count(osd) != 2:
        raise LookupError("the volume's hover")
    inter = inter.replace(osd, "inRightPanel(panels.osdWrapper, x, y) && root.edgeHover(screenState.osd, x >= width - root.edgePx || root.sideShared(\"right\"));")
    # The sidebar's: from the top over it (the sidebar from the top), or Caelestia's own, the right edge; and the sidebar
    # patches' own test of that edge, which must stay the same (atSidebarEdge: "return <it>;")
    found = set(re.findall(r"const showSidebarHover = (.*);\n", inter))
    if len(found) != 1 or inter.count("const showSidebarHover = ") != 2:
        raise LookupError("the sidebar's hover")
    edge = found.pop()
    if edge.endswith("&& withinPanelWidth(panels.sidebar, x, y)"):
        new = edge + ' && root.edgeHover(false, y < root.edgePx || root.sideShared("top"))'
    elif edge.endswith("&& y <= sidebarTriggerY"):
        new = edge + ' && root.edgeHover(false, x >= width - root.edgePx || root.sideShared("right"))'
    else:
        raise LookupError("the sidebar's hover")
    inter = inter.replace(f"const showSidebarHover = {edge};", f"const showSidebarHover = {new};")
    inter = inter.replace(f"return {edge};", f"return {new};")
    inter = swap(inter, "        if (x < bar.implicitWidth) {\n",
                 "        if (x < bar.implicitWidth && !WindowDrag.dragging) {\n", "the bar popouts' hover")
    return {"modules/drawers/Interactions.qml": inter} | components("services/WindowDrag.qml")


# The changes, in the order they're applied. Each can be turned off in the Settings app (Features page), which lists
# them by this name (patch.py --list). A change that builds on another's version of a file still fits without it, or is
# in NEEDS (tests/caelestia-overlay.sh turns each one off alone)
def screens_followed():
    # A screen's monitor looked up again when Hyprland's list of them changes (a screen rotated, its mode or scale
    # changed): Caelestia's lookup is a function call, which QML only re-runs for the properties read inside it, so a
    # screen rebuilt before Hyprland's list had its monitor kept none. Its bar then had no workspaces and the
    # special-workspace look (no monitor read as one being open: undefined isn't "")
    hypr = "services/Hypr.qml"
    h = swap(read(hypr), """    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
""", """    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        Hyprland.monitors.values; // (read: a binding calling this runs again when the monitors change)
        return Hyprland.monitorFor(screen);
""", "Hypr.monitorFor")
    rel = "modules/bar/components/workspaces/Workspaces.qml"
    w = swap(read(rel), 'readonly property bool onSpecial: monitor?.lastIpcObject.specialWorkspace?.name !== ""',
             'readonly property bool onSpecial: (monitor?.lastIpcObject.specialWorkspace?.name ?? "") !== ""',
             "the bar's special workspace check")
    return {hypr: h, rel: w}


def screen_wallpapers():
    # A wallpaper of its own for a screen, set in the Settings app (Look, Wallpaper: screens.<its description>.wallpaper
    # in ~/.config/dots/settings.json, read here as it changes); the others show Caelestia's (whose colours follow it)
    bg = "modules/background/Background.qml"
    b = swap(read(bg), "                sourceComponent: Wallpaper {}\n",
             "                sourceComponent: Wallpaper {\n                    screen: win.modelData\n                }\n",
             "the background's wallpaper")
    rel = "modules/background/Wallpaper.qml"
    w = swap(read(rel), "import QtQuick\n", "import QtQuick\nimport Quickshell\nimport Quickshell.Io\n", "its imports")
    # (Caelestia's main draws it with WallpaperImpl, whose own source follows Caelestia's: given this one)
    if "    property string source: Wallpapers.current\n" not in w and "    WallpaperImpl {\n        id: impl\n" in w:
        w = swap(w, "    WallpaperImpl {\n        id: impl\n", "    WallpaperImpl {\n        id: impl\n\n"
                 "        source: root.source // caelestia-overlay: this screen's own (screen_wallpapers)\n", "its picture")
        w = insert(w, "    property bool completed\n", "    property string source: Wallpapers.current\n")
    w = swap(w, "    property string source: Wallpapers.current\n", """    // caelestia-overlay: this screen's own wallpaper, if the Settings app has one for it
    property ShellScreen screen
    property var settings: ({})
    readonly property string own: settings[`screens.${Hypr.monitorFor(screen)?.description ?? ""}.wallpaper`] ?? ""
    property string source: typeof own === "string" && own !== "" ? own : Wallpapers.current

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
""", "its source")
    return {bg: b, rel: w}


def wallpaper_in_borders():
    # The wallpaper inside Caelestia's frame (the bar on the left, its border round the rest), not under it; and as the
    # frame comes in when the shell starts, the whole screen first, pushed in by the bar as it grows (kept clear of the
    # frame's exclusive zones, the background window left a black band where the bar would be until it was there).
    # The picture laid out at the frame's size (read once at that size, not again on every frame of the bar's growth),
    # drawn wider to the bar's edge while that moves. The visualiser and the desktop clock as Caelestia has them
    bg = "modules/background/Background.qml"
    b = swap(read(bg), """            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
""", """            Loader {
                id: wallpaper

                // caelestia-overlay: in the frame (the bar's exclusive zone, the border's), to the bar's edge as it moves
                // (where ExclusionMode.Normal put it before: the desktop widgets, ~/.config/quickshell/widgets, look for
                // those words in this file to line up with the wallpaper in the frame, not with the whole screen)
                readonly property var bar: ShellState.componentsFor(win.modelData)?.bar ?? null
                readonly property real frame: bar ? Config.border.thickness : 0
                readonly property real edge: bar?.width ?? 0

                asynchronous: true

                anchors.fill: parent
                anchors.leftMargin: bar?.exclusiveZone ?? 0
                anchors.topMargin: frame
                anchors.rightMargin: frame
                anchors.bottomMargin: frame
                transform: [
                    Scale {
                        xScale: wallpaper.width > 0 ? (win.width - wallpaper.frame - wallpaper.edge) / wallpaper.width : 1
                    },
                    Translate {
                        x: wallpaper.edge - wallpaper.anchors.leftMargin
                    }
                ]
""", "the wallpaper's place")
    return {bg: b}


def lock_main_screen():
    # The lock screen's card (clock, password, its buttons: lock_power's too) on the main screen only: the Settings
    # app's (screens.main), else the one focused when it locked; the others show the blurred background alone. Typed
    # there, the password still goes in (the one shared with the main screen's field, its dots shown there): Hyprland
    # gives the keyboard to the lock surface of the screen the pointer is on. Each screen's background its own wallpaper
    rel = "modules/lock/LockSurface.qml"
    s = read(rel)
    if s.count("        visible: Config.lock.enabled\n") < 1:
        raise LookupError("the lock card's visible")
    s = s.replace("        visible: Config.lock.enabled\n", "        visible: Config.lock.enabled && root.mainScreen\n")
    s = swap(s, "import Quickshell.Wayland\n", "import Quickshell.Wayland\nimport Quickshell.Io\nimport Quickshell.Hyprland\n",
             "its imports")
    s = swap(s, "    readonly property alias unlocking: unlockAnim.running\n", """    readonly property alias unlocking: unlockAnim.running

    // caelestia-overlay: the card on the main screen only (read at once: no screen without it while it loads)
    property string focusedAtLock
    Component.onCompleted: focusedAtLock = Hyprland.focusedMonitor?.name ?? ""
    readonly property bool mainScreen: {
        let main = "";
        try {
            main = JSON.parse(dotsSettings.text())["screens.main"] ?? "";
        } catch (e) {}
        const desc = s => Hyprland.monitorFor(s)?.description ?? "";
        if (typeof main === "string" && main && Quickshell.screens.some(s => desc(s) === main))
            return desc(screen) === main;
        return !focusedAtLock || screen?.name === focusedAtLock;
    }

    FileView {
        id: dotsSettings

        path: `${Quickshell.env("HOME")}/.config/dots/settings.json`
        blockLoading: true
        printErrors: false
    }

    // (the keyboard on another screen: the password into the same one)
    Item {
        focus: !root.mainScreen
        Keys.onPressed: event => {
            if (!root.unlocking)
                root.pam.handleKey(event);
        }
    }
""", "the main screen's card")
    # (and each screen its own wallpaper, as the desktop's: screen_wallpapers. Caelestia's CachingImage { path: }, its
    # main's Visual { source: }: whichever it is, its Wallpapers.current)
    head = "        id: wallpaperBackground\n"
    if s.count(head) != 1:
        raise LookupError("the lock's wallpaper")
    start = s.index(head)
    end = s.index("\n    }\n", start)
    if s.count("Wallpapers.current", start, end) != 1:
        raise LookupError("the lock's wallpaper")
    s = s[:start] + s[start:end].replace("Wallpapers.current", "root.screenWallpaper") + s[end:]
    s = swap(s, "    FileView {\n        id: dotsSettings\n", """    // (this screen's own wallpaper, if the Settings app has one for it: as the desktop's)
    readonly property string screenWallpaper: {
        let own = "";
        try {
            own = JSON.parse(dotsSettings.text())[`screens.${Hyprland.monitorFor(screen)?.description ?? ""}.wallpaper`] ?? "";
        } catch (e) {}
        return typeof own === "string" && own ? own : Wallpapers.current;
    }

    FileView {
        id: dotsSettings
""", "the lock's wallpaper")
    return {rel: s}


def bar_gaps():
    # The bar's popout kept while the pointer crosses a gap between two of its entries: Caelestia closed it there and
    # the next entry's opened anew (the clock's calendar closed on the way down to the status icons under it)
    bar = swap(read("modules/bar/Bar.qml"), """        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }
""", """        // caelestia-overlay: in a gap between two entries, the popout as it was (going from one entry to the next, it
        // closed there and the next one's opened anew); off the bar sideways, the drawers close it
        if (!ch)
            return;
""", "bar gaps")
    return {"modules/bar/Bar.qml": bar}


def tray_over_dock():
    # The tray, opened, grows from its end over what's before it in the bar (the dock), on top of it (the bar's colour
    # behind it), its place in the bar the closed tray's: Caelestia's grew in the bar's layout, the dock shrinking to
    # make room. The bar's hit tests (its popouts, the click that closes the tray, the right-click menu's span) find
    # the open tray where it reaches
    bar = read("modules/bar/Bar.qml")
    bar = swap(bar, """            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    Tray {
""", """            DelegateChoice {
                roleValue: "tray"
                delegate: EntryWrapper {
                    // caelestia-overlay (tray_over_dock): the closed tray's room; opened, over what's before it
                    z: 1
                    Layout.preferredHeight: trayItem.closedHeight

                    Tray {
                        id: trayItem

                        anchors.bottom: parent?.bottom
""", "the tray's entry")
    bar = swap(bar, """        return (childAt(width / 2, y) as EntryWrapper)?.entryId === "tray";
""", """        return entryAt(y)?.entryId === "tray";
""", "the tray's click test")
    # (the popouts' and the scroll's)
    old = "        const ch = childAt(width / 2, y) as EntryWrapper;\n"
    if not bar.count(old):
        raise LookupError("the popouts' entry test")
    bar = bar.replace(old, "        const ch = entryAt(y);\n")
    bar = swap(bar, """                const index = Math.floor(((y - top - tray.padding * 2 + tray.spacing) / tray.layout.implicitHeight) * tray.items.count);
""", """                const index = Math.floor(((y - top - tray.y - tray.padding * 2 + tray.spacing) / tray.layout.implicitHeight) * tray.items.count);
""", "the tray's item test")
    bar = swap(bar, """        if (y < (ws ? ws.y + ws.height : 0) || y > (tray ? tray.y : height))
""", """        if (y < (ws ? ws.y + ws.height : 0) || y > (tray ? tray.y + (tray.item?.y ?? 0) : height))
""", "the bar menu's span")
    bar = insert(bar, "    function checkPopout(y: real): void {\n", """    // caelestia-overlay (tray_over_dock): the entry at y, the open tray first where it reaches over the one before it
    function entryAt(y: real): EntryWrapper {
        for (let i = 0; i < repeater.count; i++) {
            const e = repeater.itemAt(i) as EntryWrapper;
            if (e?.entryId === "tray" && e.item && y >= e.y + e.item.y && y <= e.y + e.item.y + e.item.height)
                return e;
        }
        return childAt(width / 2, y) as EntryWrapper;
    }

""")
    tray = read("modules/bar/components/Tray.qml")
    tray = insert(tray, "    clip: true\n", """    // caelestia-overlay (tray_over_dock): its height closed, its room in the bar open or not
    readonly property real closedHeight: Config.bar.tray.compact ? Math.max(Config.bar.tray.background ? width : 0, expandIcon.implicitHeight + (Config.bar.tray.background ? Tokens.padding.extraSmall + Tokens.padding.medium : Tokens.padding.small)) : nonAnimHeight

""")
    # Open, the bar's own colour behind it (what it covers hidden, the tray itself not set apart: grey, AMOLED's black),
    # the dock's padding at its ends
    tray = swap(tray, """    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
""", """    // caelestia-overlay (tray_over_dock): open, the bar's colour behind it
    color: expanded && Config.bar.tray.compact ? Colours.tPalette.m3surface : Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
""", "the tray's colour")
    tray = swap(tray, "    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall\n",
                "    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : expanded ? Tokens.padding.large : Tokens.padding.small // caelestia-overlay: the dock's, more before the first icon open\n",
                "the tray's padding")
    return {"modules/bar/Bar.qml": bar, "modules/bar/components/Tray.qml": tray}


def split_windows():
    # Each screen's shell in four windows instead of Caelestia's one full-screen one (drawers/*.qml, whole files over
    # modules/drawers/): the left one (the bar and its popouts), the right one (sidebar, session, OSD, notifications,
    # utilities, toasts), the top one (dashboard) and the bottom one (launcher). Caelestia redrew the whole screen, in the
    # shell and in Hyprland (with the blur under it), every frame of every animation: a panel sliding in now redraws its
    # own window. Made from the drawers files as the features before this one leave them (their changes are in
    # drawers/), so it needs them all on (NEEDS_ALL), and those files exactly as they were then (SPLIT_INPUTS, their fingerprint):
    # Caelestia's changed, or a feature's patch to them, and this one is skipped (the shell as before, one window) until
    # drawers/ is made again from the new ones
    inputs = hashlib.sha256("".join(read(f"modules/drawers/{n}") for n in SPLIT_READS).encode()).hexdigest()
    if inputs != SPLIT_INPUTS:
        raise LookupError(f"the drawers files changed since drawers/ was made from them (now {inputs})")
    out = {f"modules/drawers/{n}": own(f"drawers/{n}") for n in sorted(os.listdir(os.path.join(here, "drawers")))
           if n.endswith(".qml")}
    # The lock above every menu: as it locks, the Super and power menus close, and no screen's shell holds a focus grab
    # while it's locked (Drawers.qml's, by AgrosLock.locked). Choosing Sleep left the power menu open behind the lock,
    # its grab taken up again once the shell redrew after waking, and Hyprland gave the keyboard to nothing outside it:
    # typing on the lock screen went nowhere until a click
    out |= components("services/AgrosLock.qml")
    lock = swap(read("modules/lock/Lock.qml"), "import qs.components.misc\n", "import qs.components.misc\nimport qs.services\n",
                "the lock's imports")
    out["modules/lock/Lock.qml"] = swap(lock, """        id: lock

        signal unlock
""", """        id: lock

        signal unlock

        // caelestia-overlay (split_windows): said to the shell; the Super and power menus closed as it locks
        onLockedChanged: {
            AgrosLock.locked = locked;
            if (!locked)
                return;
            for (const s of Quickshell.screens) {
                const state = ShellState.forScreen(s);
                if (state) {
                    state.launcher = false;
                    state.session = false;
                }
            }
        }
""", "the lock's state")
    # The notification sidebar and the utilities panel where PanelsLeft.qml and a mirrored PanelsRight.qml put them:
    # each keeps the larger spacing on its inner sides and the smaller (the border makes up the rest) on the screen's
    # edges, wherever those are (Caelestia's margins are for the right edge, and the top or bottom one; mirroring moves
    # the panel, not its content's margins): on the left when mirrored, at the top for a utilities panel hanging from
    # it (fromTop), at the bottom for a sidebar rising from it (fromBottom; its card's square corners there too)
    sidebar = swap(read("modules/sidebar/Wrapper.qml"), """        anchors.leftMargin: Tokens.padding.large
        anchors.margins: CUtils.clamp(anchors.leftMargin - Config.border.thickness, 0, anchors.leftMargin)
        anchors.bottomMargin: anchors.leftMargin - 2
        anchors.topMargin: 0
""", """        // caelestia-overlay (split_windows): the smaller spacing on the screen's edges, wherever they are
        anchors.leftMargin: root.LayoutMirroring.enabled ? root.edgePadding : Tokens.padding.large
        anchors.margins: root.edgePadding
        anchors.bottomMargin: root.fromBottom ? 0 : Tokens.padding.large - 2
        anchors.topMargin: root.fromBottom ? Tokens.padding.large - 2 : 0
""", "sidebar content margins")
    sidebar = swap(sidebar, "            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins\n",
                   "            implicitWidth: Tokens.sizes.sidebar.width - Tokens.padding.large - root.edgePadding\n"
                   "            fromBottom: root.fromBottom\n", "sidebar content width")
    sidebar = insert(sidebar, "    readonly property Props props: Props {}\n", """    // caelestia-overlay (split_windows): rising from the bottom (PanelsLeft.qml); its spacing on the screen's edges
    property bool fromBottom
    readonly property real edgePadding: CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large)
""", before=False)
    content = swap(read("modules/sidebar/Content.qml"), """            topLeftRadius: 0
            topRightRadius: 0
""", """            topLeftRadius: root.fromBottom ? radius : 0
            topRightRadius: root.fromBottom ? radius : 0
            bottomLeftRadius: root.fromBottom ? 0 : radius
            bottomRightRadius: root.fromBottom ? 0 : radius
""", "sidebar card corners")
    content = insert(content, "    required property ScreenState screenState\n",
                     "    // caelestia-overlay (split_windows): rising from the bottom, its square corners there\n"
                     "    property bool fromBottom\n", before=False)
    utilities = swap(read("modules/utilities/Wrapper.qml"), """        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
""", """        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
        // caelestia-overlay (split_windows): the smaller spacing on the screen's edges, wherever they are
        anchors.leftMargin: root.LayoutMirroring.enabled ? root.totalPadding - anchors.margins : anchors.margins
        anchors.topMargin: root.fromTop ? root.totalPadding - anchors.margins : anchors.margins
""", "utilities content margins")
    utilities = insert(utilities, "    property real horizontalStretch\n",
                       "    // caelestia-overlay (split_windows): hanging from the top (PanelsLeft.qml)\n    property bool fromTop\n",
                       before=False)
    return out | {"modules/sidebar/Wrapper.qml": sidebar, "modules/sidebar/Content.qml": content,
                  "modules/utilities/Wrapper.qml": utilities}


def bar_side():
    # The bar on another edge, when the Settings app says so (bar.side). The split windows' layout does most of it
    # (drawers/: barEdge, set here). On the right: the shell as with it on the left, mirrored; Caelestia's own files that
    # place things by the bar's side: the bar's content against its window's inner edge (it slides in from the screen's
    # edge), the popouts beside it (and sliding out of it), the border's exclusive zones (the bar's on the right, a
    # border's on the left), the wallpaper's frame (wallpaper_in_borders: its margins, and its growth as the bar comes
    # in), the music visualiser's and the desktop clock's margin. The panels on the right edge move to the left one
    # (drawers/PanelsRight.qml). Along the top or bottom: bar_across. Left (Caelestia's own; AgrOS's default is the
    # bottom), nothing changes
    side = setting_values().get("bar.side")
    if side not in ("right", "top", "bottom"):
        return {}
    out = {}
    d = "modules/drawers/Drawers.qml"
    out[d] = swap(read(d), '        readonly property string barEdge: "left" // bar_side\n',
                  f'        readonly property string barEdge: "{side}" // bar_side\n', "the drawers' bar edge")
    if side != "right":
        return {**out, **bar_across(side)}
    ex = "modules/drawers/Exclusions.qml"
    t = swap(read(ex), """    ExclusionZone {
        anchors.left: true
        exclusiveZone: root.bar.exclusiveZone""", """    ExclusionZone {
        anchors.right: true // caelestia-overlay: the bar on the right (bar_side)
        exclusiveZone: root.bar.exclusiveZone""", "the bar's exclusive zone")
    out[ex] = swap(t, """    ExclusionZone {
        anchors.right: true
    }""", """    ExclusionZone {
        anchors.left: true // caelestia-overlay: the border's, on the left (bar_side)
    }""", "the border's exclusive zone")
    bw = "modules/bar/BarWrapper.qml"
    out[bw] = swap(read(bw), """        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        active: root.shouldBeVisible""", """        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left // caelestia-overlay: the bar on the right, sliding in from that edge (bar_side)

        active: root.shouldBeVisible""", "the bar's content")
    cw = "modules/bar/popouts/ClipWrapper.qml"
    t = swap(read(cw), "    property real offsetScale: x > 0 || content.hasCurrent ? 0 : 1\n",
             "    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1 // caelestia-overlay: bar_side\n",
             "the popouts' open")
    t = swap(t, "    x: content.isDetached ? (parent.width - content.nonAnimWidth) / 2 : 0\n",
             "    x: content.isDetached ? (parent.width - content.nonAnimWidth) / 2 : parent.width - width // caelestia-overlay: beside the bar on the right (bar_side)\n",
             "the popouts' place")
    # (its x eased only to and from the middle, detached: against the bar it follows the popout's width as it changes,
    # else, a step behind it, each popout first stretched right, into the bar, then slid left)
    t = swap(t, """    Behavior on x {
        Anim {""", """    Behavior on x {
        enabled: content.isDetached // caelestia-overlay: bar_side

        Anim {""", "the popouts' easing")
    out[cw] = swap(t, """        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: (-implicitWidth - 5) * root.offsetScale""", """        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right // caelestia-overlay: out of the bar on the right (bar_side)
        anchors.rightMargin: (-implicitWidth - 5) * root.offsetScale""", "the popouts' slide")
    bg = "modules/background/Background.qml"
    t = read(bg)
    # (the wallpaper in the frame: wallpaper_in_borders's, when it's on)
    if "anchors.leftMargin: bar?.exclusiveZone ?? 0\n" in t:
        t = swap(t, """                anchors.leftMargin: bar?.exclusiveZone ?? 0
                anchors.topMargin: frame
                anchors.rightMargin: frame""", """                anchors.leftMargin: frame
                anchors.topMargin: frame
                anchors.rightMargin: bar?.exclusiveZone ?? 0 // caelestia-overlay: the bar on the right (bar_side)""",
                 "the wallpaper's frame")
        t = swap(t, "                        x: wallpaper.edge - wallpaper.anchors.leftMargin\n",
                 "                        x: 0 // (the bar on the right: grown from its left edge, bar_side)\n", "the wallpaper's growth")
    t = swap(t, "            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)\n",
             "            anchors.rightMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) // caelestia-overlay: bar_side\n",
             "the desktop clock's margin")
    out[bg] = t
    vi = "modules/background/Visualiser.qml"
    t = swap(read(vi), "                    anchors.leftMargin: (ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0) + Tokens.spacing.small * Config.background.visualiser.spacing\n",
             "                    anchors.rightMargin: (ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0) + Tokens.spacing.small * Config.background.visualiser.spacing // caelestia-overlay: bar_side\n",
             "the visualiser's margin")
    out[vi] = swap(t, "                    Behavior on anchors.leftMargin {\n", "                    Behavior on anchors.rightMargin {\n", "the visualiser's margin's animation")
    return out


# (bar_across: an icon or text of the bar's, upright in it turned)
UPRIGHT = "rotation: 90 // caelestia-overlay: upright, the bar turned a quarter (bar_side)"


def upright(text, opening, what):
    """text with the item whose opening lines are opening (unique) turned upright (UPRIGHT after its first line)"""
    if text.count(opening) != 1:
        raise LookupError(what)
    first = opening.split("\n")[0]
    indent = len(first) - len(first.lstrip()) + 4
    return text.replace(opening, f"{first}\n{' ' * indent}{UPRIGHT}\n" + opening[len(first) + 1:])


def bar_across(side):
    # bar_side's along the top or bottom (side): the same bar turned a quarter, its top at the left (everything in it,
    # its popouts' places, the pointer's tests and its own: as it is, its y the screen's x), as long as the screen is
    # wide; its icons and texts turned back upright (a few words, as one: the clock's date). Its popouts under or over
    # it, along it under the entry; the zones, the wallpaper's frame, the visualiser's and the desktop clock's margin on
    # its edge. A top bar's clock opens the dashboard (drawers/: in the bar's window, dropping down under the clock)
    # instead of its calendar; the bar's other entries close it
    top = side == "top"
    out = {}
    ex = "modules/drawers/Exclusions.qml"
    t = swap(read(ex), """    ExclusionZone {
        anchors.left: true
        exclusiveZone: root.bar.exclusiveZone""", f"""    ExclusionZone {{
        anchors.{side}: true // caelestia-overlay: the bar along the {side} (bar_side)
        exclusiveZone: root.bar.exclusiveZone""", "the bar's exclusive zone")
    out[ex] = swap(t, f"""    ExclusionZone {{
        anchors.{side}: true
    }}""", f"""    ExclusionZone {{
        anchors.left: true // caelestia-overlay: the border's, on the left (bar_side)
    }}""", "the border's exclusive zone")

    bw = "modules/bar/BarWrapper.qml"
    t = swap(read(bw), "    visible: width > Config.border.thickness\n",
             "    visible: implicitWidth > Config.border.thickness // caelestia-overlay: its thickness, whichever its edge (bar_side)\n",
             "the bar's shown")
    out[bw] = swap(t, """        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        active: root.shouldBeVisible""", f"""        // caelestia-overlay: the bar along the {side}: the same bar turned a quarter (its top at the left), as long as
        // the screen is wide, against its window's inner edge as it slides in (bar_side)
        x: (root.width - width) / 2
        y: {"root.height - root.contentWidth / 2" if top else "root.contentWidth / 2"} - height / 2
        height: root.width
        rotation: -90

        active: root.shouldBeVisible""", "the bar's content")

    bar = "modules/bar/Bar.qml"
    t = read(bar)
    for entry in ("OsIcon {\n                        objectName: \"taskbarLogo\"\n",
                  "Power {\n                        objectName: \"taskbarPowerButton\"\n"):
        t = upright(t, "                    " + entry, "the bar's " + entry.split()[0])
    if top:
        t = insert(t, "\n    function closeTray(): void {\n", """
    // caelestia-overlay: the dashboard the clock opened (the bar on top: bar_side)
    property bool clockDashboard

    Connections {
        function onDashboardChanged(): void {
            if (!root.screenState.dashboard)
                root.clockDashboard = false;
        }

        target: root.screenState
    }
""")
        t = swap(t, """        const id = ch.entryId;
        const top = ch.y;
""", """        const id = ch.entryId;
        const top = ch.y;

        // caelestia-overlay: the bar on top: its clock opens the dashboard, dropping down under it (in its calendar's
        // place); the bar's other entries close the one it opened (bar_side)
        if (id === "clock" && Config.dashboard.showOnHover) {
            popouts.currentCenter = (ch.item as Item).mapToItem(root, 0, (ch.item as Item).implicitHeight / 2).y ?? 0;
            popouts.hasCurrent = false;
            clockDashboard = true;
            screenState.dashboard = true;
            return;
        }
        if (clockDashboard) {
            clockDashboard = false;
            screenState.dashboard = false;
        }
""", "the clock's dashboard")
    out[bar] = t

    # The icons and texts. Those of a feature turned off in Settings (or skipped) as Caelestia has them: the bar on its
    # edge all the same, not back on the left (clock_digits' Digits, scroll_lock's LockStatus.qml, the dock)
    comps = "modules/bar/components/"
    digits = "    component Digits: Row {\n" in read(comps + "Clock.qml")
    clock = ("    component Digits: Row {\n        id: digits\n",) if digits else (
        "        StyledText {\n            Layout.alignment: Qt.AlignHCenter\n            text: Time.hourStr\n",
        "        StyledText {\n            Layout.topMargin: -parent.spacing - 4\n            Layout.alignment: Qt.AlignHCenter\n"
        "            text: Time.minuteStr\n",
        "            sourceComponent: StyledText {\n                text: Time.format(\"ss\")\n")
    locks = ("        MaterialIcon {\n            id: lockIcon\n",)
    if "            id: lockIcon\n" not in read(comps + "status/LockStatus.qml"):
        locks = ("        MaterialIcon {\n            id: capslockIcon\n", "        MaterialIcon {\n            id: numlockIcon\n")
    dock = os.path.lexists(os.path.join(dst, comps + "Dock.qml"))
    for rel, openings in (
        ("workspaces/Workspace.qml", ("        StyledText {\n            animate: true\n",
                                      "        MaterialIcon {\n            fill: 1\n            grade: 25\n",
                                      "                delegate: MaterialIcon {\n                    id: win\n",
                                      # (the focused workspace's random shape: an oval lay on its side)
                                      "        MaterialShape {\n            implicitSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small\n")),
        ("TrayItem.qml", ("    ColouredIcon {\n        id: icon\n",)),
        ("Clock.qml", clock + ("            sourceComponent: MaterialIcon {\n                text: \"calendar_month\"\n",
                               "            sourceComponent: ColumnLayout {\n                spacing: layout.spacing - 4\n",
                               "            sourceComponent: StyledText {\n                text: Time.amPmStr.toLowerCase()\n")),
        ("StatusIcons.qml", tuple(f"""                        {kind} {{
                            animate: true
                            text: {what}""" for kind, what in (("MaterialIcon", "Icons.getVolumeIcon"),
                                                                ("MaterialIcon", "Icons.getMicVolumeIcon"),
                                                                ("StyledText", "Hypr.kbLayout"),
                                                                ("MaterialIcon", "Nmcli.activeEthernet")))),
        ("status/BatteryStatus.qml", ("MaterialIcon {\n    required property color colour\n",)),
        ("status/BluetoothStatus.qml", ("        MaterialIcon {\n            animate: true\n            text: {\n",
                                        "            MaterialIcon {\n                id: device\n")),
        ("status/LockStatus.qml", locks),
        ("ActiveWindow.qml", ("    MaterialIcon {\n        id: icon\n",)),
    ) + ((("Dock.qml", ("                    IconImage {\n                        // Visual size every icon is scaled to",)),)
         if dock else ()):
        t = read(comps + rel)
        for o in openings:
            t = upright(t, o, f"{rel}'s {o.split()[0].removeprefix('delegate:')}")
        out[comps + rel] = t
    # The dock's open apps on the right of its pinned ones, where a turned column would put them on the left
    if dock:
        out[comps + "Dock.qml"] = swap(out[comps + "Dock.qml"], "    readonly property bool pinsFirst: false\n",
                                       "    readonly property bool pinsFirst: true\n", "the dock's order")
    # (the clock's hours and minutes side by side now: a colon between them, before the minutes)
    minutes = ("        Digits {\n" if digits else f"        StyledText {{\n            {UPRIGHT}\n") + \
        "            Layout.topMargin: -parent.spacing - 4\n            Layout.alignment: Qt.AlignHCenter\n            text: Time.minuteStr\n"
    out[comps + "Clock.qml"] = insert(out[comps + "Clock.qml"], minutes, f"""        // caelestia-overlay: the hours and minutes side by side, the bar along an edge: a colon between (bar_side)
        StyledText {{
            {UPRIGHT}
            Layout.topMargin: -parent.spacing - 4
            Layout.alignment: Qt.AlignHCenter
            text: ":"
            font: root.font.build()
            color: root.colour
        }}

""")

    cw = "modules/bar/popouts/ClipWrapper.qml"
    t = swap(read(cw), "    property real offsetScale: x > 0 || content.hasCurrent ? 0 : 1\n",
             "    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1 // caelestia-overlay: bar_side\n",
             "the popouts' open")
    t = swap(t, """    implicitWidth: content.implicitWidth * (1 - offsetScale)
    implicitHeight: content.implicitHeight
""", f"""    // caelestia-overlay: the bar along the {side}: the popouts {"under" if top else "over"} it, along it at their entry, sliding
    // out of it (bar_side)
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight * (1 - offsetScale)
""", "the popouts' size")
    t = swap(t, """    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;

        const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
        const diff = parent.height - Math.floor(off + content.nonAnimHeight);
        if (diff < 0)
            return off + diff;
        return Math.max(off, 0);
    }
""", f"    y: content.isDetached ? (parent.height - content.nonAnimHeight) / 2 : {'0' if top else 'parent.height - height'}\n",
             "the popouts' place across")
    t = swap(t, "    x: content.isDetached ? (parent.width - content.nonAnimWidth) / 2 : 0\n", """    x: {
        if (content.isDetached)
            return (parent.width - content.nonAnimWidth) / 2;

        const off = content.currentCenter - borderThickness - content.nonAnimWidth / 2;
        const diff = parent.width - Math.floor(off + content.nonAnimWidth);
        if (diff < 0)
            return off + diff;
        return Math.max(off, 0);
    }
""", "the popouts' place along")
    t = swap(t, "    Behavior on x {\n        Anim {", """    Behavior on x {
        enabled: root.offsetScale < 1 // caelestia-overlay: from entry to entry along the bar (bar_side)

        Anim {""", "the popouts' easing along")
    t = swap(t, "    Behavior on y {\n        enabled: root.offsetScale < 1\n",
             "    Behavior on y {\n        enabled: content.isDetached // caelestia-overlay: bar_side\n", "the popouts' easing across")
    out[cw] = swap(t, """        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: (-implicitWidth - 5) * root.offsetScale""", f"""        anchors.horizontalCenter: parent.horizontalCenter
        anchors.{side}: parent.{side} // caelestia-overlay: out of the bar along the {side} (bar_side)
        anchors.{side}Margin: (-implicitHeight - 5) * root.offsetScale""", "the popouts' slide")
    wr = "modules/bar/popouts/Wrapper.qml"
    t = swap(read(wr), "    Behavior on implicitWidth {\n        Anim {", """    Behavior on implicitWidth {
        enabled: root.offsetScale < 1 // caelestia-overlay: the bar across: its width, not its height, set as it opens (bar_side)

        Anim {""", "the popouts' width easing")
    out[wr] = swap(t, "    Behavior on implicitHeight {\n        enabled: root.offsetScale < 1\n\n", "    Behavior on implicitHeight {\n",
                   "the popouts' height easing")

    bg = "modules/background/Background.qml"
    t = read(bg)
    # (the wallpaper in the frame: wallpaper_in_borders's, when it's on)
    if "anchors.leftMargin: bar?.exclusiveZone ?? 0\n" in t:
        t = swap(t, "                readonly property real edge: bar?.width ?? 0\n",
                 "                readonly property real edge: bar?.implicitWidth ?? 0 // caelestia-overlay: its thickness, whichever its edge (bar_side)\n",
                 "the wallpaper's edge")
        t = swap(t, """                anchors.leftMargin: bar?.exclusiveZone ?? 0
                anchors.topMargin: frame
                anchors.rightMargin: frame
                anchors.bottomMargin: frame""", f"""                anchors.leftMargin: frame
                anchors.topMargin: {"bar?.exclusiveZone ?? 0 // caelestia-overlay: the bar along the top (bar_side)" if top else "frame"}
                anchors.rightMargin: frame
                anchors.bottomMargin: {"frame" if top else "bar?.exclusiveZone ?? 0 // caelestia-overlay: the bar along the bottom (bar_side)"}""",
                 "the wallpaper's frame")
        t = swap(t, """                    Scale {
                        xScale: wallpaper.width > 0 ? (win.width - wallpaper.frame - wallpaper.edge) / wallpaper.width : 1
                    },
                    Translate {
                        x: wallpaper.edge - wallpaper.anchors.leftMargin
                    }""", f"""                    Scale {{
                        yScale: wallpaper.height > 0 ? (win.height - wallpaper.frame - wallpaper.edge) / wallpaper.height : 1
                    }},
                    Translate {{
                        y: {"wallpaper.edge - wallpaper.anchors.topMargin" if top else "0 // (grown from its top edge)"}
                    }}""", "the wallpaper's growth")
    out[bg] = swap(t, "            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)\n",
                   f"            anchors.{side}Margin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness) // caelestia-overlay: bar_side\n",
                   "the desktop clock's margin")
    vi = "modules/background/Visualiser.qml"
    t = swap(read(vi), "                    anchors.leftMargin: (ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0) + Tokens.spacing.small * Config.background.visualiser.spacing\n",
             f"                    anchors.{side}Margin: (ShellState.componentsFor(root.screen)?.bar?.exclusiveZone ?? 0) + Tokens.spacing.small * Config.background.visualiser.spacing // caelestia-overlay: bar_side\n",
             "the visualiser's margin")
    out[vi] = swap(t, "                    Behavior on anchors.leftMargin {\n", f"                    Behavior on anchors.{side}Margin {{\n",
                   "the visualiser's margin's animation")
    return out


# What split_windows is made from: the features that change the drawers files, and those files' fingerprint after them
SPLIT_NEEDS = (bar_menu, bar_space_refit, edge_triggers, launcher_fullscreen, safe_triangle, sidebar_alone,
               sidebar_fit, sidebar_from_top, sidebar_not_over_popups, sidebar_shape, sidebar_with_utilities, snap_preview,
               top_edge_one_panel, tray_click, window_peek)
SPLIT_READS = ("ContentWindow.qml", "Drawers.qml", "Exclusions.qml", "Interactions.qml", "Panels.qml", "PeekLayer.qml",
               "Regions.qml", "SnapPreview.qml")
SPLIT_INPUTS = "c605ed0ecbb4187a5d4e41afe7d2d20c143acc454f3db7836a6343a2fcb1be32"


FEATURES = (
    ("launcher pin buttons", launcher),
    ("bar dock", dock),
    ("app icons for windows whose class names no app", window_icons),
    ("settings: weather location picker and system clock", nexus_region),
    ("the dock's place kept when it's off", dock_space),
    ("bluetooth pairing", bluetooth),
    ("Spotify tray icon", spotify_tray),
    ("favourites first, all A-Z", favourites_az),
    ("Super menu finds apps by what they are too: term, files...", launcher_by_kind),
    ("brightness on built-in screens only", internal_brightness),
    ("bar logo does nothing", logo_inert),
    ("popout safe triangle", safe_triangle),
    ("Steam menu: installed games only", steam_installed_only),
    ("lock screen dimmed like the login screen", lock_tint),
    ("lock screen text cursor", lock_cursor),
    ("critical battery hibernates, or suspends where it can't", battery_suspend),
    ("the power menu: log out, sleep, restart, shut down, Shut down in its colour, an update's mark", power_menu),
    ("lock screen: a wrong password said at once", lock_instant_fail),
    ("Scroll Lock icon", scroll_lock),
    ("tray A-Z", tray_az),
    ("tray: right-click opens Wine apps' own menu", tray_menu_fallback),
    ("check for updates button", updates_button),
    ("settings button in the Super menu", settings_button),
    ("AgrOS's settings in Caelestia's (Nexus)", nexus_pages),
    ("settings: quicker page changes, pages as wide as the window", nexus_snappy),
    ("settings: back and forward, no close button in its window", nexus_history),
    ("settings opened at a page (Updates from its notifications)", settings_open_at),
    ("tray opens on click", tray_click),
    ("lock badges re-read at login", lock_refresh),
    ("notification sidebar without the utilities panel", sidebar_notifs_only),
    ("notifications in neutral colours", notifs_neutral),
    ("AMOLED black: the shell's backgrounds pure black in dark mode, when Settings says so", amoled),
    ("clicking a notification runs its action and brings its app forward", notif_click),
    ("notification sidebar: no divider, ends above the utilities panel", sidebar_shape),
    ("notification sidebar: not with the power menu, closes the volume slider", sidebar_alone),
    ("notification sidebar slides down from the top", sidebar_from_top),
    ("notification sidebar closes without bouncing back", sidebar_close_settled),
    ("notification sidebar as tall as its notifications, at most half the screen, a shadow where it scrolls", sidebar_fit),
    ("notification sidebar: not opened by hovering while a pop-up shows", sidebar_not_over_popups),
    ("Super menu over fullscreen windows", launcher_fullscreen),
    ("workspaces highlighted on hover", workspace_hover),
    ("notification sidebar with Super+K, merged with the utilities panel", sidebar_with_utilities),
    ("bar right-click menu: Task Manager, floating/tiling", bar_menu),
    ("dashboard calendar and weather in the system language", dashboard_language),
    ("dashboard gauges: small changes not animated (less GPU)", gauges_settle),
    ("text cursor stops blinking 10 s after typing (less GPU)", cursor_blink_rest),
    ("lock screen comes in like the login screen", lock_intro),
    ("no volume popup at start or on a device change", osd_quiet_start),
    ("no warnings about a missing account picture", face_quiet),
    ("bar clock digits lined up", clock_digits),
    ("workspace previews on hover", workspace_preview),
    ("a calendar on hovering the bar's clock", clock_calendar),
    ("window peek: resting on a preview shows its windows alone", window_peek),
    ("lock screen sleep, restart and power off", lock_power),
    ("window snapping preview", snap_preview),
    ("panels open from the screen's very edge, not while dragging", edge_triggers),
    ("the top edge opens the dashboard or the notification sidebar, not both", top_edge_one_panel),
    ("windows fitted again when the bar's space changes", bar_space_refit),
    ("a rotated or changed screen keeps its bar's workspaces", screens_followed),
    ("a wallpaper of its own for each screen", screen_wallpapers),
    ("the wallpaper inside the bar and border", wallpaper_in_borders),
    ("lock screen on the main screen only", lock_main_screen),
    ("the bar's popout kept across the gaps between its entries", bar_gaps),
    ("the tray opens over the dock, nothing beside it squeezed", tray_over_dock),
    ("the shell in four windows, each redrawn on its own (less GPU)", split_windows),
    ("the bar on the right, top or bottom, when Settings puts it there", bar_side),
)


_values = None


def setting_values():
    """The Settings app's values (dots-settings values), read once; none when it can't be read. By the account's home,
    not $HOME: run as you from root (sudo, su), it may be root's"""
    global _values
    if _values is None:
        # (DOTS_SETTINGS: another settings command, for tests/caelestia-overlay.sh)
        cli = os.environ.get("DOTS_SETTINGS") or f"{pwd.getpwuid(os.getuid()).pw_dir}/.local/bin/dots-settings"
        try:
            _values = json.loads(subprocess.run([cli, "values"], capture_output=True, text=True).stdout)
        except (OSError, ValueError):
            _values = {}
        if not isinstance(_values, dict):
            _values = {}
    return _values


def turned_off():
    """The features turned off in the Settings app (dots-settings, setting caelestia.<function name>)"""
    return {f.__name__ for _, f in FEATURES if setting_values().get(f"caelestia.{f.__name__}") is False}


# Features that build on another's version of a file (or, the utilities sidebar, on its trigger's geometry; the sidebar's
# shape on the utilities panel's height, known while closed only with sidebar_notifs_only) and don't fit without it: off when that one is off or skipped. Several: it needs one of them (window peek: the dock's or the
# workspace preview's popout, the previews it works on), off when all are
NEEDS = {"bar_side": ("split_windows",), "nexus_snappy": ("nexus_pages",), "settings_open_at": ("nexus_pages",), "nexus_history": ("nexus_snappy",), "sidebar_shape": ("sidebar_notifs_only",), "settings_button": ("updates_button",), "top_edge_one_panel": ("sidebar_from_top",), "sidebar_from_top": ("sidebar_shape",), "sidebar_fit": ("sidebar_from_top",),
         "sidebar_with_utilities": ("sidebar_from_top",),
         "window_peek": ("dock", "workspace_preview")}
# ...and features that need every one of a list: off when any of them is off or skipped
NEEDS_ALL = {"split_windows": tuple(f.__name__ for f in SPLIT_NEEDS), "tray_over_dock": ("tray_click", "bar_menu")}

def off_with(fid):
    """What turning one off turns off too (those needing it, NEEDS_ALL's or NEEDS' alone, and so on): the Settings app
    says it on its switch (16 of them took the bar's place from the bottom back to the left, unsaid)"""
    found, todo = [], [fid]
    while todo:
        x = todo.pop(0)
        for y, ns in [*NEEDS_ALL.items(), *((k, v) for k, v in NEEDS.items() if len(v) == 1)]:
            if x in ns and y not in found:
                found.append(y)
                todo.append(y)
    return found


if sys.argv[1:] == ["--list"]:
    names = {f.__name__: name for name, f in FEATURES}
    print(json.dumps([{"id": f.__name__, "label": name, **({"also_off": [names[y] for y in off_with(f.__name__)]}
                                                            if off_with(f.__name__) else {})} for name, f in FEATURES]))
    sys.exit(0)
src, dst = sys.argv[1], sys.argv[2]
off = turned_off()
skipped = set()  # (what didn't fit: what needs it is skipped too, said as one, not "Off" as if turned off)
failed = {}  # (of those, the ones whose patch failed, not didn't fit: their error)
ok = True
labels = {f.__name__: name for name, f in FEATURES}
for name, feature in FEATURES:
    if feature.__name__ in off:
        print(f"Off: {name}")
        continue
    needs = NEEDS.get(feature.__name__, ())
    if needs and all(n in off for n in needs):
        off.add(feature.__name__)
        if any(n in skipped for n in needs):
            skipped.add(feature.__name__)
            # (only the ones that didn't fit named so: another of them may be off by your choice)
            unfit = [labels[n] for n in needs if n in skipped and n not in failed]
            broke = [f"{labels[n]} failed ({failed[n]})" for n in needs if n in failed]
            chosen = [labels[n] for n in needs if n not in skipped]
            why = ([f"{' and '.join(unfit)} didn't fit"] if unfit else []) + broke + \
                ([f"{' and '.join(chosen)} turned off"] if chosen else [])
            print(f"WARNING: {name} skipped, it needs {' or '.join(labels[n] for n in needs)}: {', '.join(why)}")
        else:
            print(f"Off: {name} (needs {' or '.join(labels[n] for n in needs)})")
        continue
    gone = [n for n in NEEDS_ALL.get(feature.__name__, ()) if n in off]
    if gone:
        off.add(feature.__name__)
        if any(n in skipped for n in gone):
            skipped.add(feature.__name__)
            print(f"WARNING: {name} skipped, it needs {' and '.join(labels[n] for n in gone)}, which didn't fit")
        else:
            print(f"Off: {name} (needs {' and '.join(labels[n] for n in gone)})")
        continue
    try:
        write(feature())
        print(f"Patched: {name}")
    except LookupError as e:
        ok = False
        off.add(feature.__name__)  # (and what builds on it: NEEDS)
        skipped.add(feature.__name__)
        print(f"WARNING: {name} skipped, this Caelestia version doesn't fit the patch ({e})")
    except Exception as e:  # any other failure skips this one, not the rest
        ok = False
        off.add(feature.__name__)
        skipped.add(feature.__name__)
        failed[feature.__name__] = f"{type(e).__name__}: {e}"
        print(f"WARNING: {name} skipped, it failed ({failed[feature.__name__]})")
# (3, not 1: Python's own exit on a crash, which caelestia-overlay must not take for a run that got to the end)
sys.exit(0 if ok else 3)
