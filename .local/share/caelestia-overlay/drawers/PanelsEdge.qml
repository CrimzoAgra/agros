// caelestia-overlay (split_windows): the panel of the top window (the dashboard), the bottom one (the launcher) or the
// left one (the bar's popouts), placed as Caelestia's Panels.qml does: one per window, the others not made

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    // top, bottom, left or none
    required property string part
    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness
    // The bar's edge (Drawers.qml): the inner area after the border, before the bar on its side (the popouts beside
    // the bar there: bar_side's change to their wrapper). none: no panel (the bar across holds its edge's)
    property string barEdge: "left"
    // (a top bar's dashboard: under its middle's screen x, -1: in the middle; Drawers.qml)
    property real dashboardAt: -1
    // The screen's panels (Drawers.qml), for the launcher
    required property var panels
    // The deformation of its blob background (the window's PanelBg), the panel drawn with it
    property matrix4x4 deform

    // (each Component's Item gives its panel as item)
    readonly property var loaded: panel.item
    readonly property var dashboard: part === "top" ? loaded?.item ?? null : null
    readonly property var launcher: part === "bottom" ? loaded?.item ?? null : null
    readonly property var popoutsWrapper: part === "left" ? loaded?.item ?? null : null
    readonly property var popouts: popoutsWrapper?.content ?? null

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: barEdge === "left" ? bar.implicitWidth : borderThickness
    anchors.rightMargin: barEdge === "right" ? bar.implicitWidth : borderThickness
    anchors.topMargin: barEdge === "top" ? bar.implicitWidth : borderThickness
    anchors.bottomMargin: barEdge === "bottom" ? bar.implicitWidth : borderThickness

    // (in a Loader filling this, so each panel's anchors are on this item, as in Caelestia's)
    Loader {
        id: panel

        anchors.fill: parent
        sourceComponent: root.part === "top" ? dashboardPanel : root.part === "bottom" ? launcherPanel : root.part === "left" ? popoutsPanel : null
    }

    Component {
        id: dashboardPanel

        Item {
            readonly property alias item: dashboard

            // (out of a top bar: shown from its edge, not slid in behind it, its text over the bar's background)
            clip: root.barEdge === "top"

            Dashboard.Wrapper {
                id: dashboard

                screenState: root.screenState

                anchors.top: parent.top
                // (in the middle, or under dashboardAt; by x, not an anchor: one let go of leaves x where it was)
                x: root.dashboardAt < 0 ? (parent.width - width) / 2 : Math.max(0, Math.min(parent.width - width, root.dashboardAt - root.anchors.leftMargin - width / 2))

                transform: Matrix4x4 {
                    matrix: root.deform
                }
            }
        }
    }

    Component {
        id: launcherPanel

        Item {
            readonly property alias item: launcher

            // (out of a bottom bar: shown from its edge, not slid in behind it, its text over the bar's background)
            clip: root.barEdge === "bottom"

            Launcher.Wrapper {
                id: launcher

                screen: root.screen
                screenState: root.screenState
                panels: root.panels

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                transform: Matrix4x4 {
                    matrix: root.deform
                }
            }
        }
    }

    Component {
        id: popoutsPanel

        Item {
            readonly property alias item: popoutsWrapper

            BarPopouts.ClipWrapper {
                id: popoutsWrapper

                screen: root.screen
                borderThickness: root.borderThickness

                content.transform: Matrix4x4 {
                    matrix: root.deform
                }
            }
        }
    }
}
