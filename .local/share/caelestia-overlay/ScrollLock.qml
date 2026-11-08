pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Scroll Lock state (caelestia-overlay). Hyprland doesn't track Scroll Lock, so ~/.local/bin/scroll-lock
// (on the Scroll Lock key) keeps it in $XDG_RUNTIME_DIR/scroll-lock
Singleton {
    id: root

    property bool on

    FileView {
        id: file

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/scroll-lock`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.on = text().trim() === "1"
        onLoadFailed: root.on = false
    }

    // The file is made at login; until it exists there's nothing to watch, so look again now and then
    Timer {
        running: !file.loaded
        interval: 2000
        repeat: true
        onTriggered: file.reload()
    }
}
