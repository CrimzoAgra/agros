pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// A window's app and icon: the app file the Super menu lists, its icon the menu's. The one lookup every icon of a
// window goes through: Caelestia's bar (utils/Icons.qml, patched to use this), the dock and its popout (through Icons),
// and the Alt+Tab switcher, each loading this file (not an import: Quickshell blocks those from outside a shell's
// folder). So they never disagree.
//   windowId(ipc): what to look a window up by (a Hyprland client: lastIpcObject): its class, or for a class many
//   apps share (steam_app_default: every Lutris game under Proton) its class and process, "steam_app_default@<pid>"
//   appEntry(id): the app file of a window (windowId, or a plain class), or a pinned app's id; null when none fits
//   iconName(id): its icon name, for Quickshell.iconPath; a Steam game with no shortcut its icon from Steam's cache
//   (steam_icon_<id>, game-focus makes it), else Steam's; "" when nothing fits
// By Quickshell's own lookup, else ~/.local/bin/app-for-window (the class's last part, a Flatpak's id, the window's
// program), asked once per class: what uses this shows the app's icon once the answer is in
Scope {
    id: root

    property var asked: ({})
    property var answers: ({})
    // Classes several apps' windows share: told apart by their process (app-for-window: a Lutris game's prefix)
    readonly property var shared: ["steam_app_default"]

    function windowId(ipc: var): string {
        const cls = ipc?.class ?? "";
        return shared.includes(cls) && ipc?.pid > 0 ? `${cls}@${ipc.pid}` : cls;
    }

    function appEntry(id: string): var {
        if (!id)
            return null;
        const [cls, ownPid] = id.split("@");
        // A Steam game (steam_app_<id>): the shortcut Steam made for it (its name, icon steam_icon_<id>); the lookup
        // by name found Steam itself
        const game = cls.match(/^steam_app_(\d+)$/);
        if (game)
            return DesktopEntries.applications.values.find(e => e.icon === `steam_icon_${game[1]}`) ?? null;
        // (a shared class names no app: Quickshell's guess by name would be one for every window of it)
        const entry = ownPid ? null : DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls);
        if (entry)
            return entry;
        if (id in answers)
            return answers[id] ? DesktopEntries.byId(answers[id]) : null;
        // (by the window's own process, else that of a window of that class)
        const pid = ownPid ?? Hyprland.toplevels.values.find(t => t.lastIpcObject?.class === cls)?.lastIpcObject.pid;
        if (pid && !asked[id]) {
            asked[id] = true;
            // (timeout: one that hangs answers nothing, not never)
            asker.createObject(root, { cls: id, command: ["timeout", "5", `${Quickshell.env("HOME")}/.local/bin/app-for-window`, cls, String(pid)] });
        }
        return null;
    }

    function iconName(id: string): string {
        const cls = (id ?? "").split("@")[0];
        const icon = appEntry(id)?.icon;
        if (icon)
            return icon;
        const game = (cls ?? "").match(/^steam_app_(\d+)$/);
        if (game)
            return Quickshell.iconPath(`steam_icon_${game[1]}`, true) ? `steam_icon_${game[1]}` : "steam";
        return "";
    }

    Component {
        id: asker

        Process {
            id: proc

            property string cls

            // Its answer once (its output, or none: not there, not runnable, timed out), then gone, once it has ended:
            // one that never answered was kept for good
            function answer(): void {
                if (!(cls in root.answers))
                    root.answers = Object.assign({}, root.answers, { [cls]: out.text.trim() });
            }

            running: true
            onRunningChanged: if (!running) Qt.callLater(() => { proc.answer(); proc.destroy(); })
            stdout: StdioCollector {
                id: out

                onStreamFinished: proc.answer()
            }
        }
    }
}
