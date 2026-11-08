// Desktop Settings: a window in Caelestia's style for the dotfiles' settings. The pages and settings come from
// ~/.local/bin/dots-settings (schema.json in ~/.local/share/dots-settings), which also saves and applies changes.
//   qs -c settings -n    open it (Super menu: "Desktop Settings", ~/.local/bin/desktop-settings)
//   DOTS_SETTINGS_PAGE=keys qs -c settings -n    open it on a page (desktop-settings keys)
//   DOTS_SETTINGS_SHOT=file.png ...              save a picture of the window and quit (to check its look)
// Closing the window quits it. Separate from Caelestia, so Caelestia updates don't touch it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string cli: `${home}/.local/bin/dots-settings`

    // Caelestia's colours: ../common/Scheme.qml (not an import: Quickshell blocks those from outside this folder)
    Loader {
        id: scheme
        source: `file://${Quickshell.shellPath("../common/Scheme.qml")}`
    }
    function c(name: string): color {
        return scheme.item?.c(name) ?? "transparent";
    }

    property var pages: []
    property string pageId: Quickshell.env("DOTS_SETTINGS_PAGE") ?? ""
    readonly property var page: pages.find(p => p.id === pageId) ?? pages[0] ?? null
    property var values: ({}) // key -> value, changed here before dots-settings has saved them

    // Changes run one at a time, in order; how to apply them (reload Hyprland...) is collected and done once they stop
    property var queue: []
    property var pendingApply: []
    // (awaitingOutput: a change's output, which says how to apply it, can come after it has exited)
    property bool awaitingOutput
    readonly property bool busy: queue.length > 0 || runner.running || awaitingOutput || applyTimer.running || applier.running
    property string error // the last save or apply that failed, shown at the bottom
    property bool closing // the window was closed: quit once the changes are saved and applied
    onBusyChanged: if (closing && !busy) Qt.quit()

    // Clicks so far: a reading of the settings started before the latest one is out of date
    property int edits: 0

    function set(key: string, value: var): void {
        error = "";
        edits++;
        schemaProc.lastText = ""; // the screen differs from the last reading now: the next one is shown (a failed save put back)
        values = Object.assign({}, values, { [key]: value });
        queue = [...queue, [cli, "set", key, JSON.stringify(value), "--later"]];
        next();
    }

    function next(): void {
        if (runner.running || !queue.length)
            return;
        runner.command = queue[0];
        queue = queue.slice(1);
        awaitingOutput = true;
        runner.running = true;
    }

    // The settings as saved: at start, after a change that failed, and every few seconds while idle (one changed
    // elsewhere, the window mode by its key, shows as it is)
    Process {
        id: schemaProc

        property int edits
        readonly property string readError: "The settings couldn't be read (run dots-settings schema in a terminal to see why)"
        property string lastText // the last schema shown: an unchanged one isn't shown again (every row rebuilt, a click
                                 // pressed on one of them was lost)

        running: true
        command: [root.cli, "schema"]
        onStarted: edits = root.edits
        stdout: StdioCollector {
            onStreamFinished: {
                // A switch flipped while it read: its old value would flip it back on screen
                if (schemaProc.edits !== root.edits || (text !== "" && text === schemaProc.lastText))
                    return;
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
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

    Timer {
        running: !root.busy && win.visible && root.pages.length > 0
        interval: 4000
        repeat: true
        onTriggered: schemaProc.running = true
    }

    Process {
        id: runner

        stderr: StdioCollector {
            id: runnerErr
        }
        // (Its output may come after it has exited: the apply is timed from here)
        stdout: StdioCollector {
            onStreamFinished: {
                const how = text.trim();
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
                root.error = runnerErr.text.trim().split("\n").pop() || "A change couldn't be saved";
                // A fresh reading, after this (one already running started before it, and is thrown away)
                schemaProc.running = false;
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
            applier.command = ["sh", "-c", "s=0; " + root.pendingApply.map(h => `"${root.cli}" apply ${h} || s=1`).join("; ") + "; exit $s"];
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
    // How a shortcut shows: "SUPER + SHIFT + Page_Down" -> "Super + Shift + Page Down"
    function pretty(keys: string): string {
        const names = { SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", SUPER_L: "Super", mouse_down: "Scroll down", mouse_up: "Scroll up", TAB: "Tab" };
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
        font.family: "Rubik"
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

    // A setting's shortcuts as chips (x removes one), + records another, and back to the default when changed
    component Shortcuts: Flow {
        id: sc

        property var setting
        property var keys: []
        readonly property bool changed: JSON.stringify(keys) !== JSON.stringify(Array.from(setting?.default ?? []))

        Layout.maximumWidth: 330
        layoutDirection: Qt.RightToLeft
        spacing: 6

        Rectangle {
            visible: sc.changed
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: resetMouse.containsMouse ? root.c("surfaceContainerHighest") : "transparent"

            Icon {
                anchors.centerIn: parent
                text: "restart_alt"
                font.pixelSize: 18
            }
            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.set(sc.setting.key, sc.setting.default)
            }
        }

        Rectangle {
            visible: !sc.setting?.modifier || sc.keys.length === 0
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
                        font.family: "CaskaydiaCove NF"
                        font.pixelSize: 12
                        color: chip.clash ? root.c("onErrorContainer") : root.c("onSurface")
                    }
                    Icon {
                        visible: chipHover.hovered
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

    FloatingWindow {
        id: win

        title: "Desktop Settings"
        implicitWidth: 900
        implicitHeight: 640
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
                Layout.preferredWidth: 220
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

                Repeater {
                    model: root.pages

                    Rectangle {
                        id: tab

                        required property var modelData
                        readonly property bool selected: root.page?.id === modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 24
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
                            onClicked: root.pageId = tab.modelData.id
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                // Whether changes are being saved and applied
                RowLayout {
                    Layout.margins: 12
                    spacing: 8
                    opacity: root.busy ? 1 : 0.7

                    Icon {
                        text: root.busy ? "sync" : "check_circle"
                        font.pixelSize: 18

                        RotationAnimation on rotation {
                            running: root.busy
                            from: 360
                            to: 0
                            duration: 1200
                            loops: Animation.Infinite
                            onStopped: parent.rotation = 0
                        }
                    }
                    Label {
                        text: root.error || (root.busy ? "Applying…" : "Changes apply right away")
                        font.pixelSize: 12
                        color: root.error ? root.c("error") : root.c("onSurfaceVariant")
                    }
                }
            }

            // The page
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

                    ColumnLayout {
                        id: pageCol

                        width: flick.width
                        spacing: 20

                        Label {
                            text: root.page?.title ?? ""
                            font.pixelSize: 26
                            font.weight: Font.Medium
                        }

                        Repeater {
                            model: root.page?.groups ?? []

                            ColumnLayout {
                                id: group

                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 8

                                Label {
                                    Layout.leftMargin: 4
                                    text: group.modelData.title
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: root.c("primary")
                                }

                                Rectangle {
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

                                        Repeater {
                                            model: group.modelData.settings

                                            RowLayout {
                                                id: row

                                                required property var modelData
                                                required property int index
                                                readonly property var value: root.values[modelData.key]

                                                Layout.fillWidth: true
                                                Layout.margins: 14
                                                spacing: 20

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: row.modelData.label
                                                        font.weight: Font.Medium
                                                    }
                                                    Label {
                                                        Layout.fillWidth: true
                                                        visible: !!row.modelData.description
                                                        text: row.modelData.description ?? ""
                                                        wrapMode: Text.WordWrap
                                                        font.pixelSize: 12
                                                        color: root.c("onSurfaceVariant")
                                                    }
                                                    Label {
                                                        readonly property var others: {
                                                            const out = [];
                                                            if (row.modelData.type === "keys" && !row.modelData.modifier)
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

                                                Switch {
                                                    visible: row.modelData.type === "bool"
                                                    checked: row.value === true
                                                    onToggled: on => root.set(row.modelData.key, on)
                                                }

                                                Choice {
                                                    visible: row.modelData.type === "choice"
                                                    options: row.modelData.options ?? []
                                                    value: row.value ?? ""
                                                    onPicked: v => root.set(row.modelData.key, v)
                                                }

                                                Shortcuts {
                                                    visible: row.modelData.type === "keys"
                                                    setting: row.modelData
                                                    keys: row.modelData.type === "keys" ? Array.from(row.value ?? []) : []
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
