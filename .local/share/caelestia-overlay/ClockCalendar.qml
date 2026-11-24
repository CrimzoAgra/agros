// caelestia-overlay: the month's calendar, hovering the bar's clock (as on Windows): the dashboard's own (Calendar.qml,
// in Caelestia's style; the month it shows, and the wheel's change of it, shared with the dashboard's). Shown by
// Bar.qml's checkPopout (the clock_calendar patch in patch.py)
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.modules.dashboard.dash as Dash

Item {
    id: root

    // (this screen's: the popout's window is on it)
    readonly property ScreenState screenState: ShellState.forScreen((QsWindow.window as QsWindow)?.screen ?? null)

    implicitWidth: 300
    implicitHeight: (calendar.item as Item)?.implicitHeight ?? 0

    Loader {
        id: calendar

        anchors.left: parent.left
        anchors.right: parent.right
        active: root.screenState !== null

        sourceComponent: Dash.Calendar {
            screenState: root.screenState
        }
    }
}
