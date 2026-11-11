#!/usr/bin/env python3
# Applies the caelestia-overlay changes to a linked copy of Caelestia (made by caelestia-overlay).
# Each feature is all-or-nothing: if any anchor is missing (new Caelestia version), that feature
# is skipped and the original files stay linked.
#   usage: patch.py <installed caelestia dir> <overlay dir>
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


def write(files):
    for rel, content in files.items():
        path = os.path.join(dst, rel)
        if os.path.lexists(path):
            os.remove(path)  # a link to the installed file: replace it, never write through it
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)


def launcher():
    rel = "modules/launcher/items/AppItem.qml"
    s = read(rel)
    if "id: favouriteIcon" not in s:
        raise LookupError("favouriteIcon")
    s = insert(s, "import Quickshell.Widgets\n", "import Quickshell.Io\n", before=False)
    s = append_block(s, own("appitem-block.qml"))
    return {rel: s}


def dock():
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
    files["modules/bar/components/Dock.qml"] = own("Dock.qml")
    files["modules/bar/popouts/DockMenu.qml"] = own("DockMenu.qml")
    return files


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
    start = s.find("        // Placeholder until the map-based location picker lands\n")
    end = s.find("        // Units\n", start)
    if start < 0 or end < 0:
        raise LookupError("the weather location placeholder")
    s = s[:start] + own("nexus-weather-block.qml") + "\n" + s[end:]
    clock = """            first: true
            last: true
            label: Tr.tr("Clock format")"""
    s = swap(s, clock, clock.replace("            last: true\n", ""), "the clock format row")
    s = insert(s, "            onSelected: item => GlobalConfig.services.clockFormat = item.value\n        }\n",
               own("nexus-time-block.qml"), before=False)
    return {rel: s, "modules/nexus/common/SuggestRow.qml": own("SuggestRow.qml")}


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


def tray_menu_fallback():
    # Right-clicking a tray icon with no standard menu (Wine apps: the Epic Games launcher) opens the app's own menu
    # (~/.local/bin/tray-menu: its ContextMenu call, which Quickshell doesn't make); it did nothing
    rel = "modules/bar/components/TrayItem.qml"
    s = read(rel)
    s = insert(s, "import Quickshell.Services.SystemTray\n", "import Quickshell\n")
    s = swap(s, """        else
            modelData.secondaryActivate();""", """        else if (!modelData.hasMenu)
            Quickshell.execDetached(["tray-menu", modelData.id]);
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
    return {rel: s}


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
    files["services/ScrollLock.qml"] = own("ScrollLock.qml")
    files["modules/bar/components/status/LockStatus.qml"] = own("LockStatus.qml")
    return files


def updates_button():
    # Super menu: a "check for updates" button right of the search bar (~/.local/bin/update-apps --check-now). Its
    # icon spins while checking; then a notification says the result (also when the menu was closed meanwhile), and
    # clicking it opens the Updates app
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
        onClicked: updatesCheck.running = true

        RotationAnimation {
            target: updatesButton.label
            property: "rotation"
            running: updatesCheck.running
            from: 360
            to: 0
            duration: 1000
            loops: Animation.Infinite
            onStopped: updatesButton.label.rotation = 0
        }

        // Closing the menu ends this process: the check runs in its own session behind a shell, so only the shell
        // (what the icon waits on) goes then, and the check still finishes and says the result
        Process {
            id: updatesCheck

            command: ["sh", "-c", 'setsid -w "$0" --check-now & wait $!', `${Quickshell.env("HOME")}/.local/bin/update-apps`]
        }
    }

""")
    return {rel: t}


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
    # shortly after start, all inside the shell
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
    old = "    readonly property bool shouldBeActive: screenState.sidebar || (screenState.utilities"
    s = swap(s, old, "    readonly property bool shouldBeActive: (screenState.utilities", "utilities shouldBeActive")
    # Its contents stay built while it's hidden, so its height is known before it ever opens: the sidebar ends where
    # its top is (sidebar_shape), on any screen
    old = "        active: root.shouldBeActive || root.visible\n"
    s = swap(s, old, "        active: true\n", "utilities loader")
    # ...and laid out: Qt doesn't lay out hidden items (the quick toggles row came out 46 px short). Closed, it sits
    # below the screen and fully transparent, which Qt doesn't draw
    old = "    visible: offsetScale < 1\n"
    s = swap(s, old, "    visible: true\n", "utilities visible")
    return {rel: s}


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
        Quickshell.execDetached(["hyprctl", "eval", `dots.focus_app(${JSON.stringify(entry)}, ${JSON.stringify(appName)}, ${launch})`]);
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
    window = read("modules/drawers/ContentWindow.qml")
    window = swap(window, "    mask: hasFullscreen ? emptyRegion : regions\n",
                  "    mask: hasFullscreen && !screenState.launcher ? emptyRegion : regions\n", "launcher mask")
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
    files = {"services/WindowPeek.qml": own("WindowPeek.qml"), "modules/drawers/PeekLayer.qml": own("PeekLayer.qml"),
             "modules/drawers/ContentWindow.qml": window}
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
    # Super+K (Caelestia's "show all") opens the notification sidebar too, with the utilities panel joined under it
    # (sidebar_shape)
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
    files["modules/bar/popouts/BarMenu.qml"] = own("BarMenu.qml")
    return files


def dashboard_language():
    # The dashboard's calendar and weather tab in the system language (LANG), not the date format's (LC_TIME, which
    # Qt.locale() follows), and the weather tab's heading with a 3-letter weekday like the rest
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
    s = swap(s, """        function onBrightnessChanged(): void {
            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }
""", """        function onBrightnessChanged(): void {
            if (root.brightnessRead)
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
    # round buttons over the dimmed wallpaper, fading in and out with the lock's content
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
            "modules/bar/popouts/WorkspacePreview.qml": own("WorkspacePreview.qml")}


# The changes, in the order they're applied. Each can be turned off in the Settings app (Features page), which lists
# them by this name (patch.py --list). A change that builds on another's version of a file still fits without it, or is
# in NEEDS (tests/caelestia-overlay.sh turns each one off alone)
FEATURES = (
    ("launcher pin buttons", launcher),
    ("bar dock", dock),
    ("app icons for windows whose class names no app", window_icons),
    ("settings: weather location picker and system clock", nexus_region),
    ("the dock's place kept when it's off", dock_space),
    ("bluetooth pairing", bluetooth),
    ("Spotify tray icon", spotify_tray),
    ("favourites first, all A-Z", favourites_az),
    ("brightness on built-in screens only", internal_brightness),
    ("bar logo does nothing", logo_inert),
    ("popout safe triangle", safe_triangle),
    ("Steam menu: installed games only", steam_installed_only),
    ("lock screen dimmed like the login screen", lock_tint),
    ("lock screen text cursor", lock_cursor),
    ("lock screen: a wrong password said at once", lock_instant_fail),
    ("Scroll Lock icon", scroll_lock),
    ("tray A-Z", tray_az),
    ("tray: right-click opens Wine apps' own menu", tray_menu_fallback),
    ("check for updates button", updates_button),
    ("tray opens on click", tray_click),
    ("lock badges re-read at login", lock_refresh),
    ("notification sidebar without the utilities panel", sidebar_notifs_only),
    ("notifications in neutral colours", notifs_neutral),
    ("clicking a notification runs its action and brings its app forward", notif_click),
    ("notification sidebar: no divider, ends above the utilities panel", sidebar_shape),
    ("notification sidebar: not with the power menu, closes the volume slider", sidebar_alone),
    ("notification sidebar slides down from the top", sidebar_from_top),
    ("notification sidebar closes without bouncing back", sidebar_close_settled),
    ("notification sidebar: not opened by hovering while a pop-up shows", sidebar_not_over_popups),
    ("Super menu over fullscreen windows", launcher_fullscreen),
    ("workspaces highlighted on hover", workspace_hover),
    ("notification sidebar with Super+K, merged with the utilities panel", sidebar_with_utilities),
    ("bar right-click menu: Task Manager, floating/tiling", bar_menu),
    ("dashboard calendar and weather in the system language", dashboard_language),
    ("lock screen comes in like the login screen", lock_intro),
    ("no volume popup at start or on a device change", osd_quiet_start),
    ("no warnings about a missing account picture", face_quiet),
    ("bar clock digits lined up", clock_digits),
    ("workspace previews on hover", workspace_preview),
    ("window peek: resting on a preview shows its windows alone", window_peek),
    ("lock screen sleep, restart and power off", lock_power),
)


def turned_off():
    """The features turned off in the Settings app (dots-settings, setting caelestia.<function name>). By the account's
    home, not $HOME: the pacman hook runs this through runuser, which may keep root's"""
    # (DOTS_SETTINGS: another settings command, for tests/caelestia-overlay.sh)
    cli = os.environ.get("DOTS_SETTINGS") or f"{pwd.getpwuid(os.getuid()).pw_dir}/.local/bin/dots-settings"
    try:
        values = json.loads(subprocess.run([cli, "values"], capture_output=True, text=True).stdout)
    except (OSError, ValueError):
        return set()
    if not isinstance(values, dict):
        return set()
    return {f.__name__ for _, f in FEATURES if values.get(f"caelestia.{f.__name__}") is False}


# Features that build on another's version of a file (or, the utilities sidebar, on its trigger's geometry) and don't
# fit without it: off when that one is off or skipped. Several: it needs one of them (window peek: the dock's or the
# workspace preview's popout, the previews it works on), off when all are
NEEDS = {"sidebar_from_top": ("sidebar_shape",), "sidebar_with_utilities": ("sidebar_from_top",),
         "window_peek": ("dock", "workspace_preview")}

if sys.argv[1:] == ["--list"]:
    print(json.dumps([{"id": f.__name__, "label": name} for name, f in FEATURES]))
    sys.exit(0)
src, dst = sys.argv[1], sys.argv[2]
off = turned_off()
ok = True
labels = {f.__name__: name for name, f in FEATURES}
for name, feature in FEATURES:
    if feature.__name__ in off:
        print(f"Off: {name}")
        continue
    needs = NEEDS.get(feature.__name__, ())
    if needs and all(n in off for n in needs):
        off.add(feature.__name__)
        print(f"Off: {name} (needs {' or '.join(labels[n] for n in needs)})")
        continue
    try:
        write(feature())
        print(f"Patched: {name}")
    except LookupError as e:
        ok = False
        off.add(feature.__name__)  # (and what builds on it: NEEDS)
        print(f"WARNING: {name} skipped, this Caelestia version doesn't fit the patch ({e})")
    except Exception as e:  # any other failure skips this one, not the rest
        ok = False
        off.add(feature.__name__)
        print(f"WARNING: {name} skipped, it failed ({type(e).__name__}: {e})")
sys.exit(0 if ok else 1)
