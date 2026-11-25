// caelestia-overlay: a page's skeleton while it's made (Nexus's pages, Pages.qml; AgrOS's sections until their settings
// are read, AgrosSections.qml): its title, a section header and rows, as grey shapes pulsing gently, where they'll be

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool header: true
    property int rows: 6

    implicitHeight: column.implicitHeight + column.anchors.topMargin

    // (the title where a page's is: at its left, over the content)
    Bone {
        id: title

        visible: root.header
        width: 220
        height: 34
        radius: Tokens.rounding.small
    }

    ColumnLayout {
        id: column

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.header ? title.height + Tokens.spacing.extraLargeIncreased : 0
        // (as wide as a page's content: PageBase's cappedWidth)
        width: Math.min(root.width, Math.max(Tokens.sizes.nexus.maxContentWidth, Math.round(root.width * 0.92)))
        spacing: Tokens.spacing.extraSmall / 2

        Bone {
            Layout.preferredWidth: 140
            Layout.preferredHeight: 16
            Layout.leftMargin: Tokens.padding.small
            Layout.bottomMargin: Tokens.spacing.medium
            radius: Tokens.rounding.extraSmall
        }

        Repeater {
            model: root.rows

            Bone {
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 60
                topLeftRadius: index === 0 ? Tokens.rounding.large : Tokens.rounding.extraSmall
                topRightRadius: topLeftRadius
                bottomLeftRadius: index === (root?.rows ?? 0) - 1 ? Tokens.rounding.large : Tokens.rounding.extraSmall // (root: null as it closes)
                bottomRightRadius: bottomLeftRadius
            }
        }
    }

    SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            to: 0.45
            duration: 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 1
            duration: 700
            easing.type: Easing.InOutSine
        }
    }

    component Bone: StyledRect {
        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
    }
}
