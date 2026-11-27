pragma Singleton

// caelestia-overlay: whether the session is locked (Lock.qml sets it; split_windows in patch.py), for what in the shell
// must stand aside for the lock screen: Drawers.qml's focus grab, which kept the keyboard from it

import Quickshell

Singleton {
    property bool locked
}
