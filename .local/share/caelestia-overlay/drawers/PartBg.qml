// caelestia-overlay (split_windows): a panel's blob background in one of the shell's windows (win, PartWindow.qml), in screen
// coordinates (Caelestia's ContentWindow.qml's PanelBg)

import QtQuick
import Quickshell
import Caelestia.Blobs
import Caelestia.Config

BlobRect {
    required property PartWindow win
    required property Item panel
    property real deformAmount: 0.15

    group: win.blobGroup
    x: (panel?.x ?? 0) + win.innerLeft
    y: (panel?.y ?? 0) + win.borderThickness
    implicitWidth: panel?.width ?? 0
    implicitHeight: panel?.height ?? 0
    radius: Tokens.rounding.extraLarge
    deformScale: (deformAmount * Config.appearance.deformScale) / 10000
}
