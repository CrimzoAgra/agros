// Desktop Settings: a window in Caelestia's style for the dotfiles' settings. The pages and settings come from
// ~/.local/bin/dots-settings (schema.json in ~/.local/share/dots-settings), which also saves and applies changes.
//   qs -c settings -n    open it (Super menu: "Desktop Settings", ~/.local/bin/desktop-settings)
//   DOTS_SETTINGS_PAGE=keys qs -c settings -n    open it on a page (desktop-settings keys)
//   DOTS_SETTINGS_SHOT=file.png ...              save a picture of the window and quit (to check its look)
// Closing the window quits it. Separate from Caelestia, so Caelestia updates don't touch it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string cli: `${home}/.local/bin/dots-settings`

    // Caelestia's colours: ../common/Scheme.qml (not an import: Quickshell blocks those from outside this folder)
    Loader {
        id: scheme
        source: `file://${Quickshell.shellPath("../common/Scheme.qml")}`
    }
    // Caelestia's fonts (../common/Scheme.qml too)
    readonly property string bodyFont: scheme.item?.body ?? "JetBrainsMono Nerd Font"
    readonly property string monoFont: scheme.item?.mono ?? "JetBrainsMono Nerd Font"
    function c(name: string): color {
        return scheme.item?.c(name) ?? "transparent";
    }

    property var pages: []
    property string pageId: Quickshell.env("DOTS_SETTINGS_PAGE") ?? ""
    readonly property var page: pages.find(p => p.id === pageId) ?? pages[0] ?? null
    property var values: ({}) // key -> value, changed here before dots-settings has saved them

    // Search (the field above the pages): every page's settings whose label, description or key has the words, each
    // once (Caelestia's options on their own pages first, not again in the list of all of them)
    property string search
    readonly property var shownPage: {
        const q = search.trim().toLowerCase();
        if (!q)
            return page;
        const groups = [], seen = {};
        let n = 0;
        for (const p of pages)
            for (const g of p.groups) {
                const hits = g.settings.filter(s => !seen[s.key] && [s.label, s.description ?? "", s.key].some(t => t.toLowerCase().includes(q)));
                hits.forEach(s => seen[s.key] = true);
                if (hits.length && n < 150) // (a word in hundreds of them: the first ones, the window stays quick)
                    groups.push({ title: `${p.title} › ${g.title}`, settings: hits.slice(0, 150 - n) });
                n += hits.length;
            }
        return { id: "search", title: groups.length ? "Search" : "Nothing found", groups };
    }
    // Groups opened (the long lists start closed): "<page>/<group>" -> true
    property var expanded: ({})
    // A choice with many options (fonts, screen modes) open as a list: its setting
    property var menu: null
    property string menuFilter
    onMenuChanged: menuFilter = ""
    // (the fields' own text, once typed in, no longer follows these: put back when they're cleared from here)
    onSearchChanged: if (searchInput.text !== search) searchInput.text = search
    onMenuFilterChanged: if (menuFilterInput.text !== menuFilter) menuFilterInput.text = menuFilter

    // Changes run one at a time, in order; how to apply them (reload Hyprland...) is collected and done once they stop
    property var queue: []
    property var pendingApply: []
    // (awaitingOutput: a change's output, which says how to apply it, can come after it has exited)
    property bool awaitingOutput
    readonly property bool busy: queue.length > 0 || runner.running || awaitingOutput || applyTimer.running || applier.running
    property string error // the last save or apply that failed, shown at the bottom
    property bool deferred // the last apply waits for a game to close (dots-settings apply said "deferred")
    property bool closing // the window was closed: quit once the changes are saved and applied
    onBusyChanged: if (closing && !busy) Qt.quit()

    // Clicks so far: a reading of the settings started before the latest one is out of date
    property int edits: 0

    function set(key: string, value: var): void {
        error = "";
        edits++;
        schemaProc.lastText = nowProc.lastText = ""; // the screen differs from the last reading now: the next one is shown (a failed save put back)
        values = Object.assign({}, values, { [key]: value });
        queue = [...queue, [cli, "set", key, JSON.stringify(value), "--later"]];
        next();
    }

    // Screens dragged on the Screens page (the "arrange" row), in Hyprland's layout pixels. Where screen i, let go at x,
    // y, goes: against the side of another screen nearest to there, sharing at least a quarter of the shorter edge,
    // lined up with its top, bottom or middle (or left, right, centre) when within 48 px of that; never over a screen.
    // Back where it was if no side fits
    function arrangeSnap(list: var, i: int, x: real, y: real): var {
        const d = list[i], others = list.filter((_, j) => j !== i);
        if (!others.length)
            return { x: 0, y: 0 };
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const align = (v, o, size, osize) => [o, o + osize - size, o + (osize - size) / 2].find(c => Math.abs(v - c) <= 48) ?? v;
        const over = (cx, cy) => others.some(o => cx < o.x + o.w && cx + d.w > o.x && cy < o.y + o.h && cy + d.h > o.y);
        let best = null, dist = Infinity;
        for (const o of others) {
            const sy = Math.min(d.h, o.h) / 4, sx = Math.min(d.w, o.w) / 4;
            const ay = align(clamp(y, o.y - d.h + sy, o.y + o.h - sy), o.y, d.h, o.h);
            const ax = align(clamp(x, o.x - d.w + sx, o.x + o.w - sx), o.x, d.w, o.w);
            for (const [cx, cy] of [[o.x + o.w, ay], [o.x - d.w, ay], [ax, o.y + o.h], [ax, o.y - d.h]]) {
                const away = Math.hypot(cx - x, cy - y);
                if (away < dist && !over(cx, cy)) {
                    best = { x: Math.round(cx), y: Math.round(cy) };
                    dist = away;
                }
            }
        }
        return best ?? { x: d.x, y: d.y };
    }
    // The layout moved so its top left is 0,0: none left of or above it (Proton games aim the mouse elsewhere there)
    function arrangeNormal(list: var): var {
        const mx = Math.min(...list.map(s => s.x)), my = Math.min(...list.map(s => s.y));
        return list.map(s => Object.assign({}, s, { x: s.x - mx, y: s.y - my }));
    }

    // Why a change failed, by the setting's label, as the app names it: dots-settings names its key ("keys.screenshot:
    // CTRL + ALT + K is Capri's (her chat): choose other keys")
    // (by loops: the pages' lists, kept in a var property, aren't JS arrays to flatMap)
    function failure(key: string, why: string): string {
        for (const p of pages)
            for (const g of p.groups)
                for (const s of g.settings)
                    if (s.key === key && why.startsWith(`${key}: `))
                        return `${s.label}: ${why.slice(key.length + 2)}`;
        return why;
    }

    // A reading of the settings (schemaProc) or of their values (nowProc), its clicks counted as it's asked for: counted
    // when it started, a click in between was overwritten by what it had read before it. One running isn't started
    // again (its count, from before that click, stays: its reading is thrown away)
    function read(proc: var): void {
        if (proc.running)
            return;
        proc.edits = edits;
        proc.running = true;
    }

    function next(): void {
        if (runner.running || !queue.length)
            return;
        runner.command = queue[0];
        queue = queue.slice(1);
        awaitingOutput = true;
        runner.running = true;
    }

    // The pages with their option lists (fonts, wallpapers...) and the settings as saved: at start, on each page shown,
    // after a change that failed or was applied (the shortcuts no setting changes, the clashes), and when the poll below
    // finds a setting come or gone (a screen plugged in, an app's autostart entry)
    Process {
        id: schemaProc

        property int edits
        readonly property string readError: "The settings couldn't be read (run dots-settings schema in a terminal to see why)"
        property string lastText // the last schema shown: an unchanged one isn't shown again (every row rebuilt, a click
                                 // pressed on one of them was lost)

        running: true
        command: [root.cli, "schema"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A switch flipped while it read: its old value would flip it back on screen
                if (schemaProc.edits !== root.edits || (text !== "" && text === schemaProc.lastText))
                    return;
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    // (not over a failed save's message: the read that save's restart killed ends here too, empty)
                    if (!root.error)
                        root.error = schemaProc.readError;
                    schemaProc.lastText = ""; // the next good reading is shown, and clears this
                    return;
                }
                if (root.error === schemaProc.readError)
                    root.error = ""; // read fine again (not a failed save's message: that one stays)
                const vals = {};
                for (const p of data.pages)
                    for (const g of p.groups)
                        for (const s of g.settings)
                            vals[s.key] = s.value;
                root.values = vals;
                root.pages = data.pages;
                schemaProc.lastText = text;
            }
        }
    }

    onPageIdChanged: root.read(schemaProc)

    // Every few seconds while idle, only the values (dots-settings now: no option lists, a fraction of the schema's
    // work): one changed elsewhere, the window mode by its key, shows as it is
    Process {
        id: nowProc

        property int edits
        property string lastText

        command: [root.cli, "now"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (nowProc.edits !== root.edits || text === nowProc.lastText)
                    return;
                let now;
                try {
                    now = JSON.parse(text);
                } catch (e) {
                    root.read(schemaProc); // (its reading says what's wrong)
                    return;
                }
                nowProc.lastText = text;
                // (the shortcuts no setting changes aren't in it: only the schema lists them)
                const known = Object.keys(root.values).filter(k => !k.startsWith("binds.")).sort().join("\n");
                if (Object.keys(now).sort().join("\n") !== known)
                    root.read(schemaProc);
                else
                    root.values = Object.assign({}, root.values, now);
            }
        }
    }

    // (a first read that failed tried again too: with none shown yet, the window stayed empty)
    Timer {
        running: !root.busy && win.visible
        interval: 4000
        repeat: true
        onTriggered: {
            if (root.pages.length)
                root.read(nowProc);
            else
                root.read(schemaProc);
        }
    }

    Process {
        id: runner

        stderr: StdioCollector {
            id: runnerErr
        }
        // (Its output may come after it has exited: the apply is timed from here)
        stdout: StdioCollector {
            onStreamFinished: {
                // (its last line: a set command's own output, a wallpaper's or a scheme's, comes before it)
                const how = text.trim().split("\n").pop();
                if (how && !root.pendingApply.includes(how))
                    root.pendingApply = [...root.pendingApply, how];
                if (root.pendingApply.length)
                    applyTimer.restart();
                root.awaitingOutput = false;
            }
        }
        // Not saved: say so, and show the settings as they really are
        onExited: code => {
            if (code !== 0) {
                root.error = root.failure(runner.command[2] ?? "", runnerErr.text.trim().split("\n").pop()) || "A change couldn't be saved";
                // A fresh reading, after this (one already running started before it, and is thrown away)
                schemaProc.running = false;
                schemaProc.edits = root.edits;
                schemaProc.running = true;
            }
            root.next();
        }
    }

    Timer {
        id: applyTimer

        // Longer for Caelestia's changes: each rebuilds and restarts the shell, so a few clicks in a row make one restart
        interval: root.pendingApply.includes("caelestia") ? 3000 : 700
        onTriggered: {
            // (an apply still running: a second start of it would be dropped)
            if (root.queue.length || runner.running || applier.running) {
                restart();
                return;
            }
            // Each one runs, and any failing shows (not only the last one's exit status)
            // (each as an argument, not pasted into the script: what a set printed besides its apply is no command)
            applier.command = ["sh", "-c", 's=0; for h; do "$0" apply "$h" || s=1; done; exit $s', root.cli, ...root.pendingApply];
            root.pendingApply = [];
            root.deferred = false;
            applier.running = true;
        }
    }

    Process {
        id: applier

        stderr: StdioCollector {
            id: applierErr
        }
        // (a game open: the change waits until it closes)
        stdout: StdioCollector {
            onStreamFinished: root.deferred = text.includes("deferred")
        }
        onExited: code => {
            if (code !== 0)
                root.error = applierErr.text.trim().split("\n").pop() || "A change couldn't be applied";
            root.read(schemaProc);
        }
    }

    // Recording a shortcut: Hyprland switches to a submap with no binds (dots-capture, user/keys.lua) so every key
    // reaches this window; Esc there switches back too. capture: { key, modifier } of the setting it's for
    property var capture: null
    property string captureHint // why the last keys weren't taken
    function startCapture(key: string, modifier: bool): void {
        captureHint = "";
        capture = { key, modifier };
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"dots-capture\")"]);
    }
    function endCapture(keys: string): void {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"]);
        const now = Array.from(values[capture?.key] ?? []);
        if (keys && capture && !now.includes(keys))
            set(capture.key, [...now, keys]);
        capture = null;
    }
    Component.onDestruction: if (capture) Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"])

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
        for (const p of pages)
            for (const g of p.groups)
                for (const s of g.settings)
                    if (s.type === "keys")
                        for (const k of values[s.key] ?? [])
                            // A "modifier + 0-9" one takes those ten keys
                            s.modifier ? [..."1234567890"].forEach(d => add(`${k} + ${d}`, s.label)) : add(k, s.label);
        return used;
    }

    Timer {
        running: !!root.capture
        interval: 20000 // given up on: the binds come back
        onTriggered: root.endCapture("")
    }

    Timer {
        running: !!Quickshell.env("DOTS_SETTINGS_SHOT") && root.pages.length > 0
        interval: 1000
        onTriggered: body.grabToImage(r => {
            r.saveToFile(Quickshell.env("DOTS_SETTINGS_SHOT"));
            Qt.quit();
        })
    }

    component Icon: Text {
        font.family: "Material Symbols Rounded"
        font.pixelSize: 22
        color: root.c("onSurfaceVariant")
    }

    component Label: Text {
        font.family: root.bodyFont
        font.pixelSize: 14
        color: root.c("onSurface")
    }

    // An on/off switch, Material style
    component Switch: Rectangle {
        id: sw

        property bool checked
        signal toggled(bool on)

        implicitWidth: 52
        implicitHeight: 32
        radius: 16
        color: checked ? root.c("primary") : root.c("surfaceContainerHighest")
        border.width: checked ? 0 : 2
        border.color: root.c("outline")

        Rectangle {
            x: sw.checked ? sw.width - width - 6 : 8
            anchors.verticalCenter: parent.verticalCenter
            width: sw.checked ? 22 : 16
            height: width
            radius: width / 2
            color: sw.checked ? root.c("onPrimary") : root.c("outline")

            Behavior on x {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    // One of a few options, as joined buttons
    component Choice: Row {
        id: choice

        property var options: []
        property string value
        signal picked(string value)

        spacing: 2

        Repeater {
            model: choice.options

            Rectangle {
                id: opt

                required property var modelData
                required property int index
                readonly property bool selected: modelData.value === choice.value

                implicitWidth: optText.implicitWidth + (choice.options.length > 5 ? 20 : 32) // many options: tighter, so the text keeps its room
                implicitHeight: 36
                topLeftRadius: index === 0 ? 18 : 4
                bottomLeftRadius: index === 0 ? 18 : 4
                topRightRadius: index === choice.options.length - 1 ? 18 : 4
                bottomRightRadius: index === choice.options.length - 1 ? 18 : 4
                color: selected ? root.c("secondaryContainer") : optMouse.containsMouse ? root.c("surfaceContainerHighest") : root.c("surfaceContainerHigh")

                Label {
                    id: optText

                    anchors.centerIn: parent
                    text: opt.modelData.label
                    font.weight: opt.selected ? Font.Medium : Font.Normal
                    color: opt.selected ? root.c("onSecondaryContainer") : root.c("onSurface")
                }

                MouseArea {
                    id: optMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!opt.selected) choice.picked(opt.modelData.value)
                }
            }
        }
    }

    // A setting's shortcuts as chips (x removes one), + records another; a fixed one's only shown
    component Shortcuts: Flow {
        id: sc

        property var setting
        property var keys: []

        Layout.maximumWidth: 330
        layoutDirection: Qt.RightToLeft
        spacing: 6

        Rectangle {
            visible: !sc.setting?.readonly && (!sc.setting?.modifier || sc.keys.length === 0)
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: addMouse.containsMouse ? root.c("surfaceContainerHighest") : root.c("surfaceContainerHigh")

            Icon {
                anchors.centerIn: parent
                text: "add"
                font.pixelSize: 18
            }
            MouseArea {
                id: addMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startCapture(sc.setting.key, !!sc.setting.modifier)
            }
        }

        Repeater {
            model: sc.keys

            Rectangle {
                id: chip

                required property string modelData
                readonly property bool clash: !sc.setting?.modifier && (root.usage[root.norm(modelData)] ?? []).length > 1

                implicitWidth: chipRow.implicitWidth + 20
                implicitHeight: 32
                radius: 10
                color: clash ? root.c("errorContainer") : root.c("surfaceContainerHighest")

                HoverHandler {
                    id: chipHover
                }

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: 4

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pretty(chip.modelData)
                        font.family: root.monoFont
                        font.pixelSize: 12
                        color: chip.clash ? root.c("onErrorContainer") : root.c("onSurface")
                    }
                    Icon {
                        visible: chipHover.hovered && !sc.setting?.readonly
                        anchors.verticalCenter: parent.verticalCenter
                        text: "close"
                        font.pixelSize: 16

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.set(sc.setting.key, sc.keys.filter(k => k !== chip.modelData))
                        }
                    }
                }
            }
        }
    }

    // A small round icon button (reset, -, +)
    component IconButton: Rectangle {
        id: ib

        property string icon
        property bool filled
        signal clicked

        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: ibMouse.containsMouse ? root.c("surfaceContainerHighest") : ib.filled ? root.c("surfaceContainerHigh") : "transparent"

        Icon {
            anchors.centerIn: parent
            text: ib.icon
            font.pixelSize: 18
        }
        MouseArea {
            id: ibMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // Text typed in, saved on Enter or on leaving the field (JSON: Ctrl+Enter, as Enter starts a new line there)
    component Field: Rectangle {
        id: field

        property string value
        property string placeholder
        property bool mono
        property bool multiline
        signal committed(string text)

        function done(): void {
            if (input.text !== value)
                committed(input.text);
        }
        // (what was typed showing the value again: a commit that changed nothing leaves value as it was, so the text
        // didn't follow it)
        function reset(): void {
            input.text = value;
        }

        implicitWidth: 260
        implicitHeight: Math.max(36, input.contentHeight + 18)
        radius: field.multiline ? 12 : 18
        color: root.c("surfaceContainerHigh")
        border.width: input.activeFocus ? 2 : 0
        border.color: root.c("primary")

        TextEdit {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 9
            text: field.value
            wrapMode: field.multiline ? TextEdit.WrapAnywhere : TextEdit.NoWrap
            clip: true
            selectByMouse: true
            font.family: field.mono ? root.monoFont : root.bodyFont
            font.pixelSize: field.mono ? 12 : 14
            color: root.c("onSurface")
            selectionColor: root.c("primary")
            selectedTextColor: root.c("onPrimary")
            Keys.onReturnPressed: event => {
                if (field.multiline && !(event.modifiers & Qt.ControlModifier)) {
                    event.accepted = false;
                    return;
                }
                field.done();
                focus = false;
            }
            Keys.onEscapePressed: {
                text = field.value;
                focus = false;
            }
            onActiveFocusChanged: if (!activeFocus) field.done()
        }
        // (typed in, the text no longer follows the value: put back once saved, or read again)
        onValueChanged: if (!input.activeFocus) input.text = value
        Label {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text && !input.activeFocus
            text: field.placeholder || "Empty"
            color: root.c("onSurfaceVariant")
        }
    }

    // A number: a slider when it has a range, and - and + around its value (which can be typed in too)
    component NumberField: RowLayout {
        id: nf

        property var setting
        property real value
        readonly property bool ranged: setting?.min !== undefined && setting?.max !== undefined
        // Its own step; with none, the slider's and - and +'s: a hundredth of the power of ten of its range (0.1 for 0-40,
        // 1 for 0-100), or with no range a tenth of that of its first value (0.1 for 1.78, 10 for 150). Fixed for the
        // field: following the value, - then + didn't come back (1 - 0.1 = 0.9, then + 0.01)
        property real first: value // (its first value: the binding broken once made, below)
        Component.onCompleted: first = value
        readonly property real step: setting?.step ?? (setting?.integer ? 1 : Math.pow(10, Math.floor(Math.log10((ranged ? (setting.max - setting.min) / 10 : Math.abs(first)) || 1)) - 1))
        property real dragged: NaN // (where the slider is while held: saved when let go)

        // Within its range, on its steps, and no 0.30000000000000004. Typed in (free) where the setting has no step of
        // its own: as typed, not snapped to a grid (16/9 stays 16/9)
        function fix(v: real, free: bool): real {
            if (setting?.min !== undefined)
                v = Math.max(setting.min, v);
            if (setting?.max !== undefined)
                v = Math.min(setting.max, v);
            if (setting?.integer)
                return Math.round(v);
            if (free && setting?.step === undefined)
                return v;
            const from = setting?.min ?? 0;
            v = from + Math.round((v - from) / step) * step;
            return parseFloat(v.toPrecision(12));
        }
        function commit(v: real, free: bool): void {
            v = fix(v, free);
            if (!isNaN(v) && v !== value)
                root.set(setting.key, v);
            else
                nfField.reset(); // (not a number, or no change once kept in range: the value shown again)
        }

        spacing: 4

        Item {
            id: slider

            readonly property real shown: isNaN(nf.dragged) ? nf.value : nf.dragged
            readonly property real frac: nf.ranged ? Math.max(0, Math.min(1, (shown - nf.setting.min) / (nf.setting.max - nf.setting.min))) : 0

            visible: nf.ranged
            implicitWidth: 170
            implicitHeight: 32

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: root.c("surfaceContainerHighest")

                Rectangle {
                    width: slider.frac * parent.width
                    height: parent.height
                    radius: 3
                    color: root.c("primary")
                }
            }
            Rectangle {
                x: slider.frac * (slider.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: root.c("primary")
            }
            MouseArea {
                function at(x: real): real {
                    return nf.fix(nf.setting.min + Math.max(0, Math.min(1, x / width)) * (nf.setting.max - nf.setting.min), false);
                }

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => nf.dragged = at(mouse.x)
                onPositionChanged: mouse => nf.dragged = at(mouse.x)
                onReleased: {
                    nf.commit(nf.dragged, false);
                    nf.dragged = NaN;
                }
            }
        }

        IconButton {
            icon: "remove"
            onClicked: nf.commit(nf.value - nf.step, false)
        }
        Field {
            id: nfField

            implicitWidth: 72
            value: String(slider.shown)
            onCommitted: text => nf.commit(parseFloat(text.replace(",", ".")), true)
        }
        IconButton {
            icon: "add"
            onClicked: nf.commit(nf.value + nf.step, false)
        }
    }

    // One of many options (fonts, a screen's modes...): the one chosen, a click lists them all
    component Dropdown: Rectangle {
        id: dd

        property var setting
        property string value
        readonly property string shown: (setting?.options ?? []).find(o => o.value === value)?.label ?? value

        implicitWidth: Math.min(300, ddRow.implicitWidth + 32)
        implicitHeight: 36
        radius: 18
        color: ddMouse.containsMouse ? root.c("surfaceContainerHighest") : root.c("surfaceContainerHigh")

        RowLayout {
            id: ddRow

            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 10
            spacing: 6

            Label {
                Layout.fillWidth: true
                Layout.maximumWidth: 240
                text: dd.shown || "None"
                elide: Text.ElideRight
                font.family: dd.setting?.preview === "font" && dd.value ? dd.value : root.bodyFont
            }
            Icon {
                text: "expand_more"
                font.pixelSize: 20
            }
        }
        MouseArea {
            id: ddMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.menu = dd.setting
        }
    }

    // Pictures to pick one from (the wallpaper)
    // The screens to drag into place, as on Windows: drawn where Hyprland has them, each one let go snaps to a side of
    // another, and every screen's position is saved (moved so the top left one is at 0,0)
    component Arrange: Item {
        id: arr

        property var setting
        property var screens: []
        onSettingChanged: screens = setting?.screens ?? []
        readonly property real minX: Math.min(...screens.map(s => s.x))
        readonly property real minY: Math.min(...screens.map(s => s.y))
        readonly property real spanW: Math.max(...screens.map(s => s.x + s.w)) - minX
        readonly property real spanH: Math.max(...screens.map(s => s.y + s.h)) - minY
        // (room around them to drag one to any side)
        readonly property real k: screens.length ? Math.min(width / (spanW * 1.8), height / (spanH * 1.8)) : 1
        readonly property real ox: (width - spanW * k) / 2
        readonly property real oy: (height - spanH * k) / 2

        implicitHeight: 240
        visible: screens.length > 0

        Repeater {
            model: arr.screens

            Rectangle {
                id: scr

                required property var modelData
                required property int index
                readonly property bool main: modelData.id === (root.values["screens.main"] ?? "")

                x: arr.ox + (modelData.x - arr.minX) * arr.k
                y: arr.oy + (modelData.y - arr.minY) * arr.k
                width: modelData.w * arr.k
                height: modelData.h * arr.k
                radius: 10
                color: drag.active ? root.c("primaryContainer") : root.c("surfaceContainerHighest")
                border.width: 2
                border.color: drag.active || hover.hovered ? root.c("primary") : root.c("outlineVariant")
                z: drag.active ? 1 : 0

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: scr.modelData.model || scr.modelData.name
                        font.weight: Font.Medium
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `${scr.modelData.name} · ${scr.modelData.w}×${scr.modelData.h}${scr.main ? " · main" : ""}`
                        font.pixelSize: 11
                        color: root.c("onSurfaceVariant")
                    }
                }

                HoverHandler {
                    id: hover

                    cursorShape: arr.screens.length > 1 ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                }
                DragHandler {
                    id: drag

                    enabled: arr.screens.length > 1
                    onActiveChanged: {
                        if (active)
                            return;
                        const list = arr.screens.map(s => Object.assign({}, s));
                        const at = root.arrangeSnap(list, scr.index, (scr.x - arr.ox) / arr.k + arr.minX, (scr.y - arr.oy) / arr.k + arr.minY);
                        list[scr.index] = Object.assign(list[scr.index], at);
                        const placed = root.arrangeNormal(list);
                        arr.screens = placed; // (drawn there at once; the reading after the apply says where Hyprland put them)
                        for (const s of placed)
                            root.set(s.key, `${s.x}x${s.y}`);
                    }
                }
            }
        }
    }

    component Pictures: Flow {
        id: pics

        property var setting
        property string value

        spacing: 8

        Repeater {
            model: pics.setting?.options ?? []

            Rectangle {
                id: pic

                required property var modelData
                readonly property bool selected: modelData.value === pics.value

                implicitWidth: 156
                implicitHeight: 92
                radius: 14
                color: pic.selected ? root.c("primary") : picMouse.containsMouse ? root.c("surfaceContainerHighest") : root.c("surfaceContainerHigh")

                // (no picture: "Same as the others", a screen's own wallpaper left to the one for every screen)
                Label {
                    visible: !pic.modelData.value
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: pic.modelData.label
                    color: pic.selected ? root.c("onPrimary") : root.c("onSurface")
                }
                Image {
                    visible: !!pic.modelData.value
                    anchors.fill: parent
                    anchors.margins: pic.selected ? 4 : 2
                    source: pic.modelData.value ? "file://" + pic.modelData.value.split("/").map(encodeURIComponent).join("/") : ""
                    sourceSize.width: 312
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                }
                MouseArea {
                    id: picMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!pic.selected) root.set(pics.setting.key, pic.modelData.value)
                }
            }
        }
    }

    FloatingWindow {
        id: win

        title: "Desktop Settings"
        implicitWidth: 980
        // Tall enough for every page in the list where the screen has the room (at 700, Startup, Shortcuts and All
        // Caelestia options were below its end, with nothing saying more were there); on a smaller screen, as before
        implicitHeight: Math.max(700, Math.min(860, (screen?.height ?? 0) - 120))
        color: root.c("surface")
        // Closed: out of sight at once, but quit only when the changes are saved and applied (quitting stops them)
        onVisibleChanged: {
            if (visible)
                return;
            // (closing set after: the timer stopped and not yet triggered reads as not busy, which would quit first)
            if (applyTimer.running) {
                applyTimer.stop();
                applyTimer.triggered();
            }
            root.closing = true;
            if (!root.busy)
                Qt.quit();
        }

        Rectangle {
            id: body

            anchors.fill: parent
            color: root.c("surface")

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // Pages
                ColumnLayout {
                    Layout.preferredWidth: 250
                    Layout.fillWidth: false // its rows fill it, which would otherwise make it take the whole window
                    Layout.fillHeight: true
                    spacing: 4

                    RowLayout {
                        Layout.margins: 8
                        Layout.bottomMargin: 16
                        spacing: 12

                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: 14
                            color: root.c("primaryContainer")

                            Icon {
                                anchors.centerIn: parent
                                text: "tune"
                                color: root.c("onPrimaryContainer")
                            }
                        }
                        Label {
                            text: "Settings"
                            font.pixelSize: 20
                            font.weight: Font.Medium
                        }
                    }

                    // Search every page
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        implicitHeight: 44
                        radius: 22
                        color: root.c("surfaceContainerHigh")
                        border.width: searchInput.activeFocus ? 2 : 0
                        border.color: root.c("primary")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 6
                            spacing: 10

                            Icon {
                                text: "search"
                                font.pixelSize: 20
                            }
                            TextInput {
                                id: searchInput

                                Layout.fillWidth: true
                                text: root.search
                                clip: true
                                font.family: root.bodyFont
                                font.pixelSize: 14
                                color: root.c("onSurface")
                                selectionColor: root.c("primary")
                                selectedTextColor: root.c("onPrimary")
                                selectByMouse: true
                                onTextEdited: root.search = text
                                Keys.onEscapePressed: root.search = ""

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !parent.text
                                    text: "Search settings"
                                    color: root.c("onSurfaceVariant")
                                }
                            }
                            IconButton {
                                visible: !!root.search
                                icon: "close"
                                onClicked: root.search = ""
                            }
                        }
                    }

                    // (more pages than fit: they scroll, and a bar beside them says so)
                    Flickable {
                        id: tabsFlick

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: tabs.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Rectangle {
                            parent: tabsFlick // (beside the list, not scrolled with it)
                            visible: tabsFlick.contentHeight > tabsFlick.height
                            x: tabsFlick.width - width
                            y: tabsFlick.visibleArea.yPosition * tabsFlick.height
                            implicitWidth: 4
                            implicitHeight: tabsFlick.visibleArea.heightRatio * tabsFlick.height
                            radius: 2
                            color: root.c("outlineVariant")
                        }

                        ColumnLayout {
                            id: tabs

                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.pages

                                Rectangle {
                                    id: tab

                                    required property var modelData
                                    readonly property bool selected: !root.search && root.page?.id === modelData.id

                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: 22
                                    color: selected ? root.c("secondaryContainer") : tabMouse.containsMouse ? root.c("surfaceContainerHigh") : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        spacing: 14

                                        Icon {
                                            text: tab.modelData.icon
                                            color: tab.selected ? root.c("onSecondaryContainer") : root.c("onSurfaceVariant")
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: tab.modelData.title
                                            font.weight: tab.selected ? Font.Medium : Font.Normal
                                            color: tab.selected ? root.c("onSecondaryContainer") : root.c("onSurface")
                                        }
                                    }

                                    MouseArea {
                                        id: tabMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.pageId = tab.modelData.id;
                                            root.search = "";
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Whether changes are being saved and applied, or why one wasn't: wrapped in the list's width (a long
                    // one widened the list, under the page beside it)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        spacing: 8
                        opacity: root.busy ? 1 : 0.7

                        Icon {
                            id: busyIcon

                            text: root.busy ? "sync" : root.error ? "error" : "check_circle"
                            font.pixelSize: 18
                            color: root.error ? root.c("error") : root.c("onSurfaceVariant")

                            RotationAnimation on rotation {
                                running: root.busy
                                from: 360
                                to: 0
                                duration: 1200
                                loops: Animation.Infinite
                                onStopped: busyIcon.rotation = 0 // (by id: an animation has no parent)
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.error || (root.busy ? "Applying…" : root.deferred ? "Applied once your game closes" : "Changes apply right away")
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            color: root.error ? root.c("error") : root.c("onSurfaceVariant")
                        }
                    }
                }

                // The page (or what the search found)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 24
                    color: root.c("surfaceContainerLow")

                    Flickable {
                        id: flick

                        anchors.fill: parent
                        anchors.margins: 24
                        contentHeight: pageCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: pageCol

                            width: flick.width
                            spacing: 20

                            Label {
                                text: root.shownPage?.title ?? ""
                                font.pixelSize: 26
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: root.shownPage?.groups ?? []

                                ColumnLayout {
                                    id: group

                                    required property var modelData
                                    readonly property string key: `${root.shownPage?.id}/${modelData.title}`
                                    // (the long lists start closed: their title opens them; a search shows them open)
                                    readonly property bool closed: !!modelData.collapsed && !root.expanded[key]

                                    visible: modelData.settings.length > 0 || !!modelData.empty
                                    Layout.fillWidth: true
                                    spacing: 8

                                    RowLayout {
                                        Layout.leftMargin: 4
                                        spacing: 4

                                        Label {
                                            text: group.modelData.title
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            color: root.c("primary")
                                        }
                                        Icon {
                                            visible: !!group.modelData.collapsed
                                            text: group.closed ? "expand_more" : "expand_less"
                                            font.pixelSize: 18
                                            color: root.c("primary")
                                        }
                                        Label {
                                            visible: group.closed
                                            text: `(${group.modelData.settings.length})`
                                            font.pixelSize: 12
                                            color: root.c("onSurfaceVariant")
                                        }

                                        TapHandler {
                                            enabled: !!group.modelData.collapsed
                                            onTapped: root.expanded = Object.assign({}, root.expanded, { [group.key]: !root.expanded[group.key] })
                                        }
                                        HoverHandler {
                                            enabled: !!group.modelData.collapsed
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                    }

                                    Rectangle {
                                        visible: !group.closed
                                        Layout.fillWidth: true
                                        implicitHeight: rows.implicitHeight + 8
                                        radius: 20
                                        color: root.c("surfaceContainer")

                                        ColumnLayout {
                                            id: rows

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 4
                                            spacing: 0

                                            Label {
                                                visible: group.modelData.settings.length === 0
                                                Layout.margins: 14
                                                text: group.modelData.empty ?? ""
                                                color: root.c("onSurfaceVariant")
                                            }

                                            Repeater {
                                                model: group.closed ? [] : group.modelData.settings

                                                // One setting: its control by its kind (one Loader each: only that one made)
                                                ColumnLayout {
                                                    id: row

                                                    required property var modelData
                                                    readonly property var value: root.values[modelData.key]
                                                    readonly property string kind: modelData.type
                                                    // (JSON and pictures: under the label, the row's whole width)
                                                    readonly property bool wide: kind === "json" || kind === "image" || kind === "arrange"
                                                    readonly property bool resettable: modelData.default !== undefined && !modelData.get && !modelData.readonly && kind !== "arrange"
                                                    readonly property bool changed: resettable && JSON.stringify(value) !== JSON.stringify(modelData.default)
                                                    // Startup's "Add an app": the skeleton row at the list's end
                                                    readonly property bool adder: !!modelData.startup_add
                                                    readonly property var control: ({
                                                            bool: boolControl,
                                                            startup: startupControl,
                                                            choice: (modelData.options?.length ?? 0) > 7 || modelData.open ? dropControl : choiceControl,
                                                            keys: keysControl,
                                                            number: numberControl,
                                                            text: textControl,
                                                            json: jsonControl,
                                                            image: imageControl,
                                                            arrange: arrangeControl
                                                        })[kind] ?? null

                                                    Layout.fillWidth: true
                                                    Layout.margins: 14
                                                    spacing: 10
                                                    // (one just removed: gone at once, not when the list is read again)
                                                    visible: row.value !== "removed"

                                                    Component {
                                                        id: boolControl

                                                        Switch {
                                                            checked: row.value === true
                                                            onToggled: on => root.set(row.modelData.key, on)
                                                        }
                                                    }
                                                    // An app started at login: minimised or as it opens, and removed
                                                    Component {
                                                        id: startupControl

                                                        Row {
                                                            spacing: 8

                                                            Choice {
                                                                options: row.modelData.options ?? []
                                                                value: row.value ?? ""
                                                                onPicked: v => root.set(row.modelData.key, v)
                                                            }
                                                            IconButton {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                icon: "delete"
                                                                onClicked: root.set(row.modelData.key, "removed")
                                                            }
                                                        }
                                                    }
                                                    Component {
                                                        id: choiceControl

                                                        Choice {
                                                            options: row.modelData.options ?? []
                                                            value: row.value ?? ""
                                                            onPicked: v => root.set(row.modelData.key, v)
                                                        }
                                                    }
                                                    Component {
                                                        id: dropControl

                                                        Dropdown {
                                                            setting: row.modelData
                                                            value: row.value ?? ""
                                                        }
                                                    }
                                                    Component {
                                                        id: keysControl

                                                        Shortcuts {
                                                            setting: row.modelData
                                                            keys: Array.from(row.value ?? [])
                                                        }
                                                    }
                                                    Component {
                                                        id: numberControl

                                                        NumberField {
                                                            setting: row.modelData
                                                            value: row.value ?? 0
                                                        }
                                                    }
                                                    Component {
                                                        id: textControl

                                                        Field {
                                                            value: row.value ?? ""
                                                            placeholder: row.modelData.placeholder ?? ""
                                                            onCommitted: text => root.set(row.modelData.key, text)
                                                        }
                                                    }
                                                    Component {
                                                        id: jsonControl

                                                        Field {
                                                            mono: true
                                                            multiline: true
                                                            value: JSON.stringify(row.value ?? null, null, JSON.stringify(row.value ?? null).length > 60 ? 2 : 0)
                                                            onCommitted: text => {
                                                                try {
                                                                    root.set(row.modelData.key, JSON.parse(text));
                                                                } catch (e) {
                                                                    root.error = `${row.modelData.label}: not valid JSON`;
                                                                }
                                                            }
                                                        }
                                                    }
                                                    Component {
                                                        id: arrangeControl

                                                        Arrange {
                                                            setting: row.modelData
                                                        }
                                                    }
                                                    Component {
                                                        id: imageControl

                                                        Pictures {
                                                            setting: row.modelData
                                                            value: row.value ?? ""
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        visible: !row.adder
                                                        spacing: 20

                                                        // (an app's icon, Startup's)
                                                        IconImage {
                                                            visible: row.kind === "startup"
                                                            Layout.rightMargin: -6
                                                            implicitSize: 32
                                                            source: visible ? Quickshell.iconPath(row.modelData.icon ?? "", "application-x-executable") : ""
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 3

                                                            Label {
                                                                Layout.fillWidth: true
                                                                text: row.modelData.label
                                                                font.weight: Font.Medium
                                                                wrapMode: Text.WordWrap
                                                            }
                                                            Label {
                                                                Layout.fillWidth: true
                                                                visible: !!row.modelData.description
                                                                text: row.modelData.description ?? ""
                                                                wrapMode: Text.WordWrap
                                                                font.pixelSize: 12
                                                                color: root.c("onSurfaceVariant")
                                                            }
                                                            // AgrOS's say on it (one of Caelestia's options it relies on)
                                                            Label {
                                                                Layout.fillWidth: true
                                                                visible: !!row.modelData.note
                                                                text: row.modelData.note ?? ""
                                                                wrapMode: Text.WordWrap
                                                                font.pixelSize: 12
                                                                color: root.c("tertiary")
                                                            }
                                                            Label {
                                                                readonly property var others: {
                                                                    const out = [];
                                                                    if (row.kind === "keys" && !row.modelData.modifier)
                                                                        for (const k of Array.from(row.value ?? []))
                                                                            for (const l of root.usage[root.norm(k)] ?? [])
                                                                                if (l !== row.modelData.label && !out.includes(l))
                                                                                    out.push(l);
                                                                    return out;
                                                                }

                                                                Layout.fillWidth: true
                                                                visible: others.length > 0
                                                                text: "Also used by: " + others.join(", ")
                                                                wrapMode: Text.WordWrap
                                                                font.pixelSize: 12
                                                                color: root.c("error")
                                                            }
                                                        }

                                                        Loader {
                                                            // (shortcuts wrap past this: a Flow is as wide as all of them in a row otherwise)
                                                            Layout.maximumWidth: row.kind === "keys" ? 330 : Number.POSITIVE_INFINITY
                                                            active: !row.wide
                                                            sourceComponent: row.control
                                                            enabled: !row.modelData.readonly
                                                            opacity: row.modelData.readonly && row.kind !== "keys" ? 0.5 : 1
                                                        }

                                                        // Back to the default. Its place kept while there's nothing to
                                                        // reset: shown only then, it pushed the control left under the
                                                        // pointer, and a second click on + hit this instead
                                                        IconButton {
                                                            visible: row.resettable
                                                            opacity: row.changed ? 1 : 0
                                                            enabled: row.changed
                                                            icon: "restart_alt"
                                                            onClicked: root.set(row.modelData.key, row.modelData.default)
                                                        }
                                                    }

                                                    // "Add an app": a dashed outline of an app's row, + where its icon
                                                    // goes; the installed apps to choose from (the menu, as a dropdown's)
                                                    Item {
                                                        id: adderRow

                                                        visible: row.adder
                                                        Layout.fillWidth: true
                                                        implicitHeight: 56

                                                        Shape {
                                                            id: dashes

                                                            anchors.fill: parent
                                                            preferredRendererType: Shape.CurveRenderer

                                                            ShapePath {
                                                                strokeColor: adderMouse.containsMouse ? root.c("primary") : root.c("outline")
                                                                strokeWidth: 1.5
                                                                strokeStyle: ShapePath.DashLine
                                                                dashPattern: [4, 3]
                                                                fillColor: adderMouse.containsMouse ? root.c("surfaceContainerHigh") : "transparent"

                                                                PathRectangle {
                                                                    x: 1
                                                                    y: 1
                                                                    width: dashes.width - 2
                                                                    height: dashes.height - 2
                                                                    radius: 16
                                                                }
                                                            }
                                                        }
                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 12
                                                            anchors.rightMargin: 16
                                                            spacing: 14

                                                            Rectangle {
                                                                implicitWidth: 32
                                                                implicitHeight: 32
                                                                radius: 16
                                                                color: root.c("surfaceContainerHighest")

                                                                Icon {
                                                                    anchors.centerIn: parent
                                                                    text: "add"
                                                                    font.pixelSize: 20
                                                                    color: root.c("primary")
                                                                }
                                                            }
                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2

                                                                Label {
                                                                    text: row.modelData.label
                                                                    font.weight: Font.Medium
                                                                }
                                                                Label {
                                                                    Layout.fillWidth: true
                                                                    text: row.modelData.description ?? ""
                                                                    elide: Text.ElideRight
                                                                    font.pixelSize: 12
                                                                    color: root.c("onSurfaceVariant")
                                                                }
                                                            }
                                                            // (where an app's choice goes: its outline)
                                                            Rectangle {
                                                                implicitWidth: 150
                                                                implicitHeight: 12
                                                                radius: 6
                                                                color: root.c("surfaceContainerHighest")
                                                            }
                                                        }
                                                        MouseArea {
                                                            id: adderMouse

                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.menu = row.modelData
                                                        }
                                                    }

                                                    Loader {
                                                        active: row.wide
                                                        visible: active
                                                        Layout.fillWidth: true
                                                        sourceComponent: row.control
                                                        enabled: !row.modelData.readonly
                                                        opacity: row.modelData.readonly ? 0.5 : 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // A dropdown's list: every option (a filter for long ones), the chosen one marked
            Rectangle {
                id: menuView

                readonly property var options: (root.menu?.options ?? []).filter(o => !root.menuFilter || o.label.toLowerCase().includes(root.menuFilter.toLowerCase()))

                anchors.fill: parent
                visible: !!root.menu
                color: Qt.rgba(0, 0, 0, 0.6)
                onVisibleChanged: if (visible) menuFilterInput.forceActiveFocus()

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.menu = null
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 440
                    height: Math.min(parent.height - 80, menuCol.implicitHeight + 32)
                    radius: 24
                    color: root.c("surfaceContainerHigh")

                    MouseArea {
                        anchors.fill: parent // (a click inside isn't one outside)
                    }

                    ColumnLayout {
                        id: menuCol

                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        Label {
                            Layout.leftMargin: 8
                            text: root.menu?.label ?? ""
                            font.pixelSize: 18
                            font.weight: Font.Medium
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: 20
                            color: root.c("surfaceContainerHighest")

                            TextInput {
                                id: menuFilterInput

                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.menuFilter
                                clip: true
                                font.family: root.bodyFont
                                font.pixelSize: 14
                                color: root.c("onSurface")
                                onTextEdited: root.menuFilter = text
                                Keys.onEscapePressed: root.menu = null
                                Keys.onReturnPressed: if (menuView.options.length === 1) {
                                    root.set(root.menu.key, menuView.options[0].value);
                                    root.menu = null;
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !parent.text
                                    text: "Filter"
                                    color: root.c("onSurfaceVariant")
                                }
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            implicitHeight: contentHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: menuView.options

                            delegate: Rectangle {
                                id: item

                                required property var modelData
                                readonly property bool selected: modelData.value === root.values[root.menu?.key]

                                width: ListView.view.width
                                implicitHeight: 40
                                radius: 20
                                color: selected ? root.c("secondaryContainer") : itemMouse.containsMouse ? root.c("surfaceContainerHighest") : "transparent"

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    text: item.modelData.label || "None"
                                    elide: Text.ElideRight
                                    font.family: root.menu?.preview === "font" && item.modelData.value ? item.modelData.value : root.bodyFont
                                    color: item.selected ? root.c("onSecondaryContainer") : root.c("onSurface")
                                }
                                MouseArea {
                                    id: itemMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!item.selected)
                                            root.set(root.menu.key, item.modelData.value);
                                        root.menu = null;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Recording a shortcut
            Rectangle {
                anchors.fill: parent
                visible: !!root.capture
                color: Qt.rgba(0, 0, 0, 0.6)
                focus: visible
                onVisibleChanged: if (visible) forceActiveFocus()

                property var held: []

                Keys.onPressed: event => {
                    event.accepted = true;
                    if (event.key === Qt.Key_Escape && !event.modifiers)
                        return root.endCapture("");
                    if (root.isModifierKey(event.key)) {
                        held = root.modifiers(event.modifiers);
                        return;
                    }
                    if (!root.capture.modifier) {
                        const mods = root.modifiers(event.modifiers);
                        const k = event.key;
                        const alone = (k >= Qt.Key_F1 && k <= Qt.Key_F35) || k === Qt.Key_Print || k === Qt.Key_Pause;
                        if (!alone && !mods.some(m => m !== "SHIFT"))
                            return root.captureHint = "Hold Super, Ctrl or Alt with it";
                        root.endCapture([...mods, root.keyName(event)].join(" + "));
                    }
                }
                // Caelestia's "mod + 0-9" ones take modifiers alone: recorded when they're let go
                Keys.onReleased: event => {
                    event.accepted = true;
                    if (root.capture?.modifier && root.isModifierKey(event.key) && held.length) {
                        // Shift alone would take Shift + 1-0 (!, @...) from typing
                        if (!held.some(m => m !== "SHIFT"))
                            return root.captureHint = "Shift alone would stop !, @... being typed: add Super, Ctrl or Alt";
                        root.endCapture(held.join(" + "));
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.endCapture("")
                }

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: 420
                    implicitHeight: 150
                    radius: 24
                    color: root.c("surfaceContainerHigh")

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "keyboard"
                            font.pixelSize: 32
                            color: root.c("primary")
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.capture?.modifier ? "Press and let go of the modifier keys" : "Press the new shortcut"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.captureHint || "Esc or a click cancels"
                            font.pixelSize: 12
                            color: root.c("onSurfaceVariant")
                        }
                    }
                }
            }
        }
    }
}
