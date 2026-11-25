pragma Singleton
pragma ComponentBehavior: Bound

// caelestia-overlay: AgrOS's settings for Nexus (its AgrOS pages and rows: AgrosPage.qml, AgrosRow.qml): the pages,
// their groups and settings with their current values, from dots-settings (its schema: the same as ~/.local/bin's
// dots-settings gives scripts), and each change made through it, saved one at a time, in order (dots-settings set
// --later), then applied together, as the old Settings app did: Hyprland's and the others' a moment after the last
// click; Caelestia's (a rebuild and restart of the shell, Nexus with it) once Nexus is closed (flush(), from Nexus.qml).
// A change shows at once; the whole schema is read again once the changes are all saved

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
    // How the saved changes apply (dots-settings apply's): the ones waiting for the moment after the last click, and
    // the shell's restart, waiting for Nexus to close
    property var pendingApply: []
    property bool restartHeld
    // The last change that didn't save, or didn't apply: why (shown on the page)
    property string error

    // Recording a shortcut (AgrosKeyCapture.qml): Hyprland switches to a submap with no binds (dots-capture,
    // user/keys.lua) so every key reaches Nexus; Esc there switches back too. capture: { key, modifier } of the setting
    property var capture: null
    property string captureHint // why the last keys weren't taken
    function startCapture(key: string, modifier: bool): void {
        captureHint = "";
        capture = { key, modifier };
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"dots-capture\")"]);
    }
    function endCapture(keys: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"]);
        const now = Array.from(byKey[capture?.key]?.value ?? []);
        if (keys && capture && !now.includes(keys))
            set(capture.key, [...now, keys]);
        capture = null;
    }

    function modifiers(m: int): var {
        return [[Qt.MetaModifier, "SUPER"], [Qt.ControlModifier, "CTRL"], [Qt.AltModifier, "ALT"], [Qt.ShiftModifier, "SHIFT"]].filter(([bit]) => m & bit).map(([, name]) => name);
    }
    // A key as Hyprland names it (xkb names, any case); one with no name here by its code (code:N)
    function keyName(event: var): string {
        const k = event.key;
        if ((k >= Qt.Key_A && k <= Qt.Key_Z) || (k >= Qt.Key_0 && k <= Qt.Key_9))
            return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35)
            return "F" + (k - Qt.Key_F1 + 1);
        // Keys Shift doesn't change: by name, as Caelestia's own shortcuts are (so a clash with them shows)
        const keys = {
            [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab", [Qt.Key_Space]: "Space", [Qt.Key_Return]: "Return",
            [Qt.Key_Escape]: "Escape", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
            [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
            [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Print]: "Print",
            [Qt.Key_Pause]: "Pause"
        };
        if (keys[k])
            return keys[k];
        // With Shift or AltGr, Qt names the symbol it types (Shift+7 is "/" on some layouts) but Hyprland matches the key
        // itself: the number row by its digit (codes 10-19, as Caelestia's SUPER + SHIFT + 1...), any other by its code
        if (event.modifiers & (Qt.ShiftModifier | Qt.GroupSwitchModifier)) {
            const code = event.nativeScanCode;
            return code >= 10 && code <= 19 ? String((code - 9) % 10) : `code:${code}`;
        }
        const names = {
            [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal", [Qt.Key_Comma]: "Comma", [Qt.Key_Period]: "Period",
            [Qt.Key_Slash]: "Slash", [Qt.Key_Backslash]: "Backslash"
        };
        return names[k] ?? `code:${event.nativeScanCode}`;
    }
    function isModifierKey(k: int): bool {
        return [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Shift].includes(k);
    }
    // How a shortcut shows: "SUPER + SHIFT + Page_Down" -> "Super + Shift + Page Down", "mouse:272" -> "Left mouse button"
    function pretty(keys: string): string {
        const names = { SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", SUPER_L: "Super", mouse_down: "Scroll down", mouse_up: "Scroll up", TAB: "Tab", "mouse:272": "Left mouse button", "mouse:273": "Right mouse button", "mouse:274": "Middle mouse button" };
        return keys.split(/\s*\+\s*/).map(p => names[p] ?? p.replace(/_/g, " ")).join(" + ");
    }
    // Shortcuts used by more than one action: normalised shortcut -> the labels using it
    function norm(keys: string): string {
        const parts = keys.split(/\s*\+\s*/).map(p => p.toLowerCase());
        return [...parts.slice(0, -1).sort(), parts[parts.length - 1]].join("+");
    }
    readonly property var usage: {
        const used = {};
        const add = (k, label) => (used[norm(k)] = used[norm(k)] ?? []).push(label);
        for (const key in byKey) {
            const s = byKey[key];
            if (s.type === "keys")
                for (const k of s.value ?? [])
                    // A "modifier + 0-9" one takes those ten keys
                    s.modifier ? [..."1234567890"].forEach(d => add(`${k} + ${d}`, s.label)) : add(k, s.label);
        }
        return used;
    }

    function page(id: string): var {
        return pages.find(p => p.id === id) ?? null;
    }

    // Whether Nexus's nav search finds a page (PageRegistry's): what's typed in its name, what it's about, or one of
    // AgrOS's settings on it (its agros: dots-settings's pages shown there)
    function matches(nav: var, text: string): bool {
        const q = text.trim().toLowerCase();
        const has = t => String(t ?? "").toLowerCase().includes(q);
        return !q || has(nav.label) || has(nav.description) || (nav.agros ?? []).some(id => (page(id)?.groups ?? []).some(g => (g.settings ?? []).some(s => has(s.label) || has(s.description))));
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
        error = "";
        queue = [...queue, [key, JSON.stringify(value)]];
        next();
    }

    // Nexus closed: the shell's restart, if a change needs it (detached: it ends this shell, and what this shell started)
    function flush(): void {
        applyTimer.stop();
        const hows = [...pendingApply.filter(h => h !== "caelestia"), ...(restartHeld || pendingApply.includes("caelestia") ? ["caelestia"] : [])];
        pendingApply = [];
        restartHeld = false;
        if (hows.length)
            Quickshell.execDetached(["sh", "-c", 'for h; do "$0" apply "$h"; done', cli, ...hows]);
    }

    function next(): void {
        if (setter.running || !queue.length)
            return;
        setter.command = [cli, "set", queue[0][0], queue[0][1], "--later"];
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
        // (its last line: how to apply it; a set command's own output comes before it)
        stdout: StdioCollector {
            onStreamFinished: {
                const how = text.trim().split("\n").pop();
                if (how === "caelestia")
                    root.restartHeld = true;
                else if (how && !root.pendingApply.includes(how))
                    root.pendingApply = [...root.pendingApply, how];
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.error = setterErr.text.trim().split("\n").pop() || "A change couldn't be saved";
                console.warn(`AgrOS settings: ${command.slice(1).join(" ")} failed: ${setterErr.text}`);
            }
            if (!root.queue.length) {
                root.reload();
                applyTimer.restart();
            }
            root.next();
        }
    }

    Timer {
        id: applyTimer

        interval: 700
        onTriggered: {
            if (setter.running || applier.running || root.queue.length) {
                restart();
                return;
            }
            if (!root.pendingApply.length)
                return;
            applier.command = ["sh", "-c", 's=0; for h; do "$0" apply "$h" || s=1; done; exit $s', root.cli, ...root.pendingApply];
            root.pendingApply = [];
            applier.running = true;
        }
    }

    Process {
        id: applier

        stderr: StdioCollector {
            id: applierErr
        }
        onExited: code => {
            if (code !== 0)
                root.error = applierErr.text.trim().split("\n").pop() || "A change couldn't be applied";
        }
    }

    Timer {
        running: !!root.capture
        interval: 20000 // given up on: the binds come back
        onTriggered: root.endCapture("")
    }

    Component.onCompleted: reload()
}
