pragma ComponentBehavior: Bound

// caelestia-overlay (split_windows, bar_side): with the bar along the top or bottom, the right window's panels that move
// to the left border's window (Drawers.qml) instead: a top bar's notification centre and its pop-ups at the bottom-left
// (the pop-ups in the corner, the centre rising from the bottom above them; the top right is the dashboard's), a bottom
// bar's keep-awake panel (utilities) at the top-left, dropping down (the bottom right is the bar's). Placed as
// PanelsRight.qml places them, turned over; there, its own copies kept shut (its away)

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar as Bar
import qs.modules.notifications as Notifications
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities

Item {
    id: root

    // notifs, utilities or none
    required property string part
    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness
    property string barEdge: "left"
    // The right window's panels (PanelsRight.qml), these placed by them as there; the bar's popouts
    required property var others
    required property var popouts
    // The deformations of their blob backgrounds (Drawers.qml), each panel drawn with its own
    property matrix4x4 deform
    property matrix4x4 sidebarDeform
    property matrix4x4 rawDeform

    readonly property var loaded: panel.item
    readonly property var notifications: part === "notifs" ? loaded?.notifications ?? null : null
    readonly property var sidebar: part === "notifs" ? loaded?.sidebar ?? null : null
    readonly property var utilities: part === "utilities" ? loaded?.utilities ?? null : null

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.topMargin: barEdge === "top" ? bar.implicitWidth : borderThickness
    anchors.bottomMargin: barEdge === "bottom" ? bar.implicitWidth : borderThickness

    Loader {
        id: panel

        anchors.fill: parent
        sourceComponent: root.part === "notifs" ? notifsPanel : root.part === "utilities" ? utilitiesPanel : null
    }

    Component {
        id: notifsPanel

        Item {
            readonly property alias notifications: notifications
            readonly property alias sidebar: sidebar

            // (each panel's own anchors mirrored, onto the left; what's inside it as it is)
            Notifications.Wrapper {
                id: notifications

                LayoutMirroring.enabled: true
                screenState: root.screenState
                sidebarPanel: sidebar
                osdPanel: root.others.osdWrapper
                sessionPanel: root.others.sessionWrapper
                utilitiesPanel: root.others.utilities

                anchors.bottom: parent.bottom
                anchors.bottomMargin: -5
                anchors.right: parent.right

                transform: Matrix4x4 {
                    matrix: root.deform
                }
            }

            Sidebar.Wrapper {
                id: sidebar

                LayoutMirroring.enabled: true
                screenState: root.screenState
                fromBottom: true

                // PanelsRight.qml's turned over: above the pop-ups, as tall as what's in it, at most half the screen;
                // closed, both edges as far down, out of sight below the screen; its bottom stays on the border as
                // opening overshoots, its top springs
                readonly property real fit: Math.min(fitHeight, root.screen.height / 2, parent.height - notifications.height)
                readonly property real slide: (notifications.height + fit + 5) * offsetScale
                anchors.bottom: notifications.top
                anchors.bottomMargin: -notifications.anchors.bottomMargin - Math.max(0, slide)
                height: fit - Math.min(0, slide)
                anchors.right: parent.right

                transform: Matrix4x4 {
                    matrix: root.sidebarDeform
                }
            }
        }
    }

    Component {
        id: utilitiesPanel

        Item {
            readonly property alias utilities: utilities

            Utilities.Wrapper {
                id: utilities

                LayoutMirroring.enabled: true
                screenState: root.screenState
                sidebar: root.others.sidebar
                popouts: root.popouts
                horizontalStretch: 1
                fromTop: true
                deformMatrix: root.rawDeform

                // (dropping down from the top: its slide on the top, not the bottom)
                anchors.top: parent.top
                anchors.topMargin: (-implicitHeight - 5) * offsetScale
                anchors.right: parent.right

                transform: Matrix4x4 {
                    matrix: root.deform
                }
            }
        }
    }
}
