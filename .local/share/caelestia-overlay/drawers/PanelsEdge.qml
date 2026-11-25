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

    // top, bottom or left
    required property string part
    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness
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
    anchors.leftMargin: bar.implicitWidth

    // (in a Loader filling this, so each panel's anchors are on this item, as in Caelestia's)
    Loader {
        id: panel

        anchors.fill: parent
        sourceComponent: root.part === "top" ? dashboardPanel : root.part === "bottom" ? launcherPanel : popoutsPanel
    }

    Component {
        id: dashboardPanel

        Item {
            readonly property alias item: dashboard

            Dashboard.Wrapper {
                id: dashboard

                screenState: root.screenState

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top

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
