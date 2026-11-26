pragma Singleton

// caelestia-overlay: the Super menu's update check (updates_button in patch.py), here so it outlives the menu: the
// menu closed and opened again while it runs, its button still spins. The check runs in its own session behind a
// shell, so a restart of the shell ends only the shell, and the check still finishes and says the result

import Quickshell
import Quickshell.Io

Singleton {
    readonly property alias running: check.running

    function start(): void {
        check.running = true;
    }

    Process {
        id: check

        command: ["sh", "-c", 'setsid -w "$0" --check-now & wait $!', `${Quickshell.env("HOME")}/.local/bin/update-apps`]
    }
}
