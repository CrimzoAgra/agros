pragma Singleton

// caelestia-overlay: window peek, like Windows' Aero Peek. Resting the pointer on a live preview for a moment shows
// what it shows alone on the desktop: a window's (the dock's popout) that window, a workspace's (the bar's workspace
// picker) every window on it; leaving the preview brings everything back. Every other window on that screen fades out
// (dots.peek_screen in ~/.config/caelestia/user/windows.lua: a tag and its rule), so the windows shown are as Hyprland
// draws them, title bars and all, over the real desktop, widgets included; nothing else about the windows changes (no
// focus, workspace or stacking change), and taking the tag off gives each window its own opacity back. Windows on a
// workspace not being shown (another one, or minimised): every window on the screen fades out and pictures of them are
// drawn over the desktop instead (PeekLayer.qml), as showing their workspace would move your view

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    // The preview under the pointer, and what's shown alone (after the delay; then at once moving between previews):
    // a window (HyprlandToplevel) or a workspace (HyprlandWorkspace)
    property QtObject hovered
    property QtObject shown
    // ...its workspace
    readonly property HyprlandWorkspace workspace: (shown as HyprlandWorkspace) ?? (shown as HyprlandToplevel)?.workspace ?? null
    // ...shown as pictures (PeekLayer.qml), on this screen: windows not on a workspace being shown
    readonly property var pictured: shown && !onScreen(workspace) ? windowsOf(shown) : []
    readonly property HyprlandMonitor picturedOn: pictured.length > 0 ? (workspace?.monitor ?? null) : null

    function enter(target: QtObject): void {
        hovered = target;
        leave.stop();
        if (!target)
            return;
        if (shown)
            shown = target;
        else
            delay.restart();
    }

    function exit(target: QtObject): void {
        if (hovered !== target)
            return;
        hovered = null;
        delay.stop();
        leave.restart();
    }

    // The windows a target shows: the window, or the workspace's (those mapped)
    function windowsOf(target: QtObject): var {
        const ws = target as HyprlandWorkspace;
        if (ws)
            return ws.toplevels.values.filter(w => w.lastIpcObject?.mapped);
        const win = target as HyprlandToplevel;
        return win ? [win] : [];
    }

    // The workspace on its screen, or its special workspace being shown
    function onScreen(ws: HyprlandWorkspace): bool {
        const mon = ws?.monitor;
        if (!mon)
            return false;
        const special = mon.lastIpcObject.specialWorkspace?.name ?? "";
        return ws === mon.activeWorkspace || (special !== "" && ws.name === special);
    }

    // What Hyprland should have: the screen peeked and the windows kept there (addresses, "0x..."; none while pictures
    // are drawn), as JSON; else none
    readonly property string wanted: {
        const mon = shown ? workspace?.monitor : null;
        if (!mon)
            return "";
        const keep = onScreen(workspace) ? windowsOf(shown).map(w => `0x${w.address}`) : [];
        return JSON.stringify([mon.name, ...keep]);
    }
    property string applied: "?" // (unknown at start: put right at once)

    // One hyprctl at a time, in order: the last one asked for wins
    function sync(): void {
        if (runner.running || wanted === applied)
            return;
        runner.target = wanted;
        // (each a Lua string: JSON's quoting, of names and addresses that are plain ASCII)
        runner.command = ["hyprctl", "eval", wanted !== "" ? `dots.peek_screen(${JSON.parse(wanted).map(s => JSON.stringify(s)).join(", ")})` : "dots.peek_end()"];
        runner.running = true;
    }

    onWantedChanged: sync()
    // (also when the shell starts: no window left see-through by one that crashed mid-peek)
    Component.onCompleted: sync()

    Process {
        id: runner

        property string target

        // Failed (Hyprland not ready, its config not loaded so no dots.peek_screen): asked again a moment later, not
        // taken as done, so the start's clean-up of windows left see-through isn't lost; each time later (a config
        // without dots.peek_screen for good: once a minute, not a hyprctl every 2 s all session)
        onExited: code => {
            if (code === 0) {
                retry.interval = 2000;
                root.applied = target;
                root.sync();
            } else {
                retry.interval = Math.min(retry.interval * 2, 60000);
                retry.restart();
            }
        }
    }

    Timer {
        id: retry

        interval: 2000
        onTriggered: root.sync()
    }

    // Your view changing meanwhile (another workspace, a special one, another screen): the peek ends
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root.shown && ["workspace", "workspacev2", "activespecial", "activespecialv2", "focusedmon", "focusedmonv2"].includes(event.name))
                root.shown = null;
        }
    }

    // As long as Windows waits before peeking
    Timer {
        id: delay

        interval: 450
        onTriggered: root.shown = root.hovered
    }

    // (going from one preview to the next: no fade out and back in between)
    Timer {
        id: leave

        interval: 120
        onTriggered: {
            if (!root.hovered)
                root.shown = null;
        }
    }
}
