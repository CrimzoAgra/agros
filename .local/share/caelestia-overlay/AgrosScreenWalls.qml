pragma ComponentBehavior: Bound

// caelestia-overlay: the screens on Nexus's Wallpapers page, where they stand (as arranged on Display), each showing its
// wallpaper (its own, or the one for every screen). One clicked: its own wallpaper to pick under them (or the same as
// the others). Shown with more than one screen

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    readonly property var screens: AgrosSettings.byKey["screens.layout"]?.screens ?? []
    property string selected // (a screen's id)

    function wallOf(s: var): string {
        const own = AgrosSettings.byKey[`screens.${s.id}.wallpaper`]?.value || "";
        const path = own || Wallpapers.current || "";
        return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
    }

    visible: screens.length > 1
    spacing: Tokens.spacing.extraSmall / 2

    StyledRect {
        id: arr

        readonly property real minX: Math.min(...root.screens.map(s => s.x))
        readonly property real minY: Math.min(...root.screens.map(s => s.y))
        readonly property real spanW: Math.max(...root.screens.map(s => s.x + s.w)) - minX
        readonly property real spanH: Math.max(...root.screens.map(s => s.y + s.h)) - minY
        readonly property real k: root.screens.length ? Math.min((width - 48) / spanW, (height - 48) / spanH) : 1

        Layout.fillWidth: true
        implicitHeight: Math.min(340, Math.round(width * 0.4))
        topLeftRadius: Tokens.rounding.large
        topRightRadius: Tokens.rounding.large
        bottomLeftRadius: root.selected ? Tokens.rounding.extraSmall : Tokens.rounding.large
        bottomRightRadius: bottomLeftRadius
        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

        Repeater {
            model: root.screens

            StyledClippingRect {
                id: scr

                required property var modelData
                readonly property bool chosen: modelData.id === root.selected

                x: (arr.width - arr.spanW * arr.k) / 2 + (modelData.x - arr.minX) * arr.k
                y: (arr.height - arr.spanH * arr.k) / 2 + (modelData.y - arr.minY) * arr.k
                width: modelData.w * arr.k - 6
                height: modelData.h * arr.k - 6
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHighest

                Image {
                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 600
                    source: root.wallOf(scr.modelData)
                }

                StyledRect {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.padding.small
                    implicitWidth: name.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: name.implicitHeight + Tokens.padding.small
                    radius: Tokens.rounding.full
                    color: scr.chosen ? Colours.palette.m3primary : Colours.palette.m3surfaceContainer

                    StyledText {
                        id: name

                        anchors.centerIn: parent
                        text: scr.modelData.name
                        color: scr.chosen ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        font: Tokens.font.label.medium
                    }
                }

                StyledRect {
                    anchors.fill: parent
                    color: "transparent"
                    radius: scr.radius
                    border.width: scr.chosen ? 3 : 1
                    border.color: scr.chosen ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                }

                StateLayer {
                    anchors.fill: parent
                    radius: scr.radius
                    onClicked: root.selected = scr.chosen ? "" : scr.modelData.id
                }
            }
        }
    }

    StyledText {
        visible: !root.selected
        Layout.leftMargin: Tokens.padding.small
        Layout.topMargin: Tokens.spacing.small
        text: "Click a screen to give it a wallpaper of its own. Screens without one share the main wallpaper."
        color: Colours.palette.m3outline
        font: Tokens.font.label.medium
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    AgrosRow {
        visible: !!root.selected
        Layout.fillWidth: true
        key: root.selected ? `screens.${root.selected}.wallpaper` : ""
        last: true
    }
}
