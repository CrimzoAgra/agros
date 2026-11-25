// caelestia-overlay (split_windows): the right window's panels (sidebar, session, OSD, notifications, utilities,
// toasts), as Caelestia's Panels.qml (with the overlay's changes to it) lays them out: they're placed against each other,
// so they stay together in one window

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.bar as Bar
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.utilities.toasts as Toasts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness
    // The bar's edge (Drawers.qml). On the right: these panels against the left edge instead, each placed (and slid in)
    // as its mirror image (LayoutMirroring on each one's own anchors, not inherited: what's inside a panel isn't
    // mirrored). Along the top or bottom: where they are, after the bar
    property string barEdge: "left"
    readonly property bool barRight: barEdge === "right"
    // The bar's popouts (the left window's), for the utilities panel
    required property var popouts
    // Which of these are in the left border's window instead (the bar along the top or bottom: PanelsLeft.qml), theirs
    // here kept shut (a state of their own, never open) and out of the way: notifs (the notification centre and its
    // pop-ups) or utilities; that window's sidebar, the one the utilities panel goes as wide as when it's open
    property string away
    property var awaySidebar

    ScreenState {
        id: shut

        modelData: root.screen
    }

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: barEdge === "left" ? bar.implicitWidth : borderThickness
    anchors.rightMargin: barRight ? bar.implicitWidth : borderThickness
    anchors.topMargin: barEdge === "top" ? bar.implicitWidth : borderThickness
    anchors.bottomMargin: barEdge === "bottom" ? bar.implicitWidth : borderThickness

    Item {
        id: osdWrapper

        LayoutMirroring.enabled: root.barRight
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sessionWrapper.anchors.rightMargin + session.width * (1 - session.offsetScale)
        clip: sidebar.visible || session.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            LayoutMirroring.enabled: root.barRight
            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: sidebar.visible || session.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications

        LayoutMirroring.enabled: root.barRight
        screenState: root.screenState
        height: root.away === "notifs" ? 0 : implicitHeight
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper

        LayoutMirroring.enabled: root.barRight
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)
        clip: sidebar.visible

        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight

        Session.Wrapper {
            id: session

            LayoutMirroring.enabled: root.barRight
            screenState: root.screenState
            sidebarVisible: sidebar.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Utilities.Wrapper {
        id: utilities

        LayoutMirroring.enabled: root.barRight
        screenState: root.away === "utilities" ? shut : root.screenState
        sidebar: root.away === "notifs" && root.awaySidebar ? root.awaySidebar : sidebar
        popouts: root.popouts

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts

        LayoutMirroring.enabled: root.barRight
        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Tokens.padding.medium
    }

    Sidebar.Wrapper {
        id: sidebar

        LayoutMirroring.enabled: root.barRight
        screenState: root.away === "notifs" ? shut : root.screenState
        // (the utilities panel away: to the bottom)
        readonly property real utilitiesRoom: root.away === "utilities" ? 0 : utilities.implicitHeight - (Tokens.padding.large - 2)

        anchors.top: notifications.bottom
        anchors.bottom: parent.bottom
        // Its grey card ends where that panel's background starts (the card sits its inner bottom spacing above this
        // edge): that panel's height whether open or not (sidebar_notifs_only keeps it built), less that spacing
        anchors.bottomMargin: utilitiesRoom + slide
        anchors.right: parent.right
        // Both edges move together: closed, it's its bottom edge's distance from the top (plus 5) up, out of sight
        readonly property real slide: (parent.height - utilitiesRoom + 5) * offsetScale
        // ...except at the end of opening, as the curve overshoots (slide below 0): its top stays on the border (going
        // past, it came away from it for a moment, an inward notch at its top-left); its bottom springs as before
        anchors.topMargin: -notifications.anchors.topMargin - Math.max(0, slide)
    }
}
