pragma Singleton
pragma ComponentBehavior: Bound

// caelestia-overlay: AgrOS's settings for Nexus (its AgrOS pages and rows: AgrosPage.qml, AgrosRow.qml): the pages,
// their groups and settings with their current values, from dots-settings (its schema: the same as ~/.local/bin's
// dots-settings gives scripts), and each change made through it (dots-settings set: applied as it's made, one at a
// time, in order). A change shows at once; the whole schema is read again once the changes are all applied

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string cli: `${Quickshell.env("HOME")}/.local/bin/dots-settings`
    property var pages: []
    // Every setting by its key (the same objects as in pages): rows look themselves up here
    property var byKey: ({})
    property bool loaded
    property var queue: []
    property bool again

    function page(id: string): var {
        return pages.find(p => p.id === id) ?? null;
    }

    function reload(): void {
        if (schema.running)
            again = true;
        else
            schema.running = true;
    }

    function set(key: string, value: var): void {
        const s = byKey[key];
        if (s) {
            s.value = value;
            root.byKeyChanged();
        }
        queue = [...queue, [key, JSON.stringify(value)]];
        next();
    }

    function next(): void {
        if (setter.running || !queue.length)
            return;
        setter.command = [cli, "set", queue[0][0], queue[0][1]];
        queue = queue.slice(1);
        setter.running = true;
    }

    onPagesChanged: {
        const m = {};
        for (const p of pages)
            for (const g of p.groups ?? [])
                for (const s of g.settings ?? [])
                    m[s.key] = s;
        byKey = m;
    }

    Process {
        id: schema

        command: [root.cli, "schema"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.pages = JSON.parse(text).pages ?? [];
                    root.loaded = true;
                } catch (e) {
                    console.warn(`AgrOS settings: the schema didn't read: ${e}`);
                }
            }
        }
        onExited: {
            if (root.again) {
                root.again = false;
                running = true;
            }
        }
    }

    Process {
        id: setter

        stderr: StdioCollector {
            id: setterErr
        }
        onExited: code => {
            if (code !== 0)
                console.warn(`AgrOS settings: ${command.slice(1).join(" ")} failed: ${setterErr.text}`);
            if (!root.queue.length)
                root.reload();
            root.next();
        }
    }

    Component.onCompleted: reload()
}
