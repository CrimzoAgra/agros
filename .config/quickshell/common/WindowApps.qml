import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// A window's app and icon: the app file the Super menu lists, its icon the menu's. The one lookup every icon of a
// window goes through: Caelestia's bar (utils/Icons.qml, patched to use this), the dock and its popout (through Icons),
// and the Alt+Tab switcher, each loading this file (not an import: Quickshell blocks those from outside a shell's
// folder). So they never disagree.
//   appEntry(cls): the app file of a window class (or an app id, a pinned app's), null when none fits
//   iconName(cls): its icon name, for Quickshell.iconPath; a Steam game with no shortcut its icon from Steam's cache
//   (steam_icon_<id>, game-focus makes it), else Steam's; "" when nothing fits
// By Quickshell's own lookup, else ~/.local/bin/app-for-window (the class's last part, a Flatpak's id, the window's
// program), asked once per class: what uses this shows the app's icon once the answer is in
Scope {
    id: root

    property var asked: ({})
    property var answers: ({})

    function appEntry(cls: string): var {
        if (!cls)
            return null;
        // A Steam game (steam_app_<id>): the shortcut Steam made for it (its name, icon steam_icon_<id>); the lookup
        // by name found Steam itself
        const game = cls.match(/^steam_app_(\d+)$/);
        if (game)
            return DesktopEntries.applications.values.find(e => e.icon === `steam_icon_${game[1]}`) ?? null;
        const entry = DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls);
        if (entry)
            return entry;
        if (cls in answers)
            return answers[cls] ? DesktopEntries.byId(answers[cls]) : null;
        // (by the process of a window of that class)
        const pid = Hyprland.toplevels.values.find(t => t.lastIpcObject?.class === cls)?.lastIpcObject.pid;
        if (pid && !asked[cls]) {
            asked[cls] = true;
            asker.createObject(root, { cls: cls, command: [`${Quickshell.env("HOME")}/.local/bin/app-for-window`, cls, String(pid)] });
        }
        return null;
    }

    function iconName(cls: string): string {
        const icon = appEntry(cls)?.icon;
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

            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    root.answers = Object.assign({}, root.answers, { [proc.cls]: text.trim() });
                    Qt.callLater(proc.destroy);
                }
            }
        }
    }
}
