pragma ComponentBehavior: Bound

// caelestia-overlay: the page Nexus opens on, AgrOS's: the settings most often looked for, on four cards (Look,
// Screens, Windows, Sound & network), each with a button to its whole page. Look: the wallpaper, light or dark, the
// colour scheme. Screens: where they stand and the main one, night light. Windows: floating or tiling, title bars,
// focus. Sound & network: the volume, the output, Wi-Fi and Bluetooth

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
    readonly property var screens: AgrosSettings.byKey["screens.layout"]?.screens ?? []

    // A page of Nexus's by its icon (its labels are translated)
    function open(icon: string): void {
        const i = PageRegistry.pages.findIndex(p => p.icon === icon);
        if (i >= 0)
            nState.currentPageIdx = i;
    }

    title: "Settings"
    Component.onCompleted: AgrosSettings.reload()

    GridLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        columns: width > 760 ? 2 : 1
        columnSpacing: Tokens.spacing.large
        rowSpacing: Tokens.spacing.large

        // Look
        Card {
            icon: "palette"
            title: "Look"
            more: "Wallpaper & style"
            onOpen: root.open("palette")

            StyledClippingRect {
                id: wall

                Layout.fillWidth: true
                implicitHeight: width * 9 / 16
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainerHigh

                Image {
                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 600
                    source: Wallpapers.current ? `file://${Wallpapers.current}` : ""
                }

                StateLayer {
                    anchors.fill: parent
                    radius: wall.radius
                    onClicked: root.open("palette")
                }
            }

            AgrosRow {
                key: "look.mode"
                first: true
            }

            AgrosRow {
                key: "look.scheme"
                last: true
            }
        }

        // Screens
        Card {
            icon: "monitor"
            title: "Screens"
            more: "Display"
            onOpen: root.open("monitor")

            // Where they stand (dragged into place on Display)
            StyledRect {
                id: mini

                readonly property real minX: Math.min(...root.screens.map(s => s.x))
                readonly property real minY: Math.min(...root.screens.map(s => s.y))
                readonly property real spanW: Math.max(...root.screens.map(s => s.x + s.w)) - minX
                readonly property real spanH: Math.max(...root.screens.map(s => s.y + s.h)) - minY
                readonly property real k: root.screens.length ? Math.min((width - 32) / spanW, (height - 32) / spanH) : 1

                Layout.fillWidth: true
                implicitHeight: width * 9 / 16
                radius: Tokens.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                Repeater {
                    model: root.screens

                    StyledRect {
                        id: scr

                        required property var modelData
                        readonly property bool main: modelData.id === (AgrosSettings.byKey["screens.main"]?.value ?? "")

                        x: (mini.width - mini.spanW * mini.k) / 2 + (modelData.x - mini.minX) * mini.k
                        y: (mini.height - mini.spanH * mini.k) / 2 + (modelData.y - mini.minY) * mini.k
                        width: modelData.w * mini.k - 4
                        height: modelData.h * mini.k - 4
                        radius: Tokens.rounding.small
                        color: main ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            text: scr.modelData.name
                            color: scr.main ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: root.open("monitor")
                }
            }

            AgrosRow {
                key: "screens.main"
                first: true
            }

            AgrosRow {
                key: "nightlight"
                last: true
            }
        }

        // Windows
        Card {
            icon: "select_window"
            title: "Windows"
            more: "Windows"
            onOpen: root.open("select_window")

            AgrosRow {
                key: "windows.mode"
                first: true
            }

            AgrosRow {
                key: "windows.titlebars"
            }

            AgrosRow {
                key: "windows.focus"
                last: true
            }
        }

        // Sound & network
        Card {
            icon: "volume_up"
            title: "Sound & network"
            more: "Audio"
            onOpen: root.open("volume_up")

            SliderRow {
                first: true
                icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                label: Audio.sink?.description || Audio.sink?.nickname || "Output"
                valueLabel: Strings.percentOne(value)
                value: Audio.volume
                enabled: !Audio.muted
                onMoved: v => Audio.setVolume(v)
            }

            ToggleRow {
                text: "Wi-Fi"
                subtext: !Nmcli.wifiEnabled ? "Off" : Nmcli.active?.ssid ?? (Nmcli.activeEthernet ? "Ethernet connected" : "Not connected")
                checked: Nmcli.wifiEnabled
                onToggled: Nmcli.enableWifi(checked, () => {})
            }

            ToggleRow {
                last: true
                text: "Bluetooth"
                subtext: !root.adapter ? "No adapter" : !root.adapter.enabled ? "Off" : `${root.adapter.devices.values.filter(d => d.connected).length} connected`
                checked: root.adapter?.enabled ?? false
                onToggled: if (root.adapter) root.adapter.enabled = checked
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.small

                TextButton {
                    type: ButtonBase.Text
                    text: "Network"
                    onClicked: root.open("wifi")
                }

                TextButton {
                    type: ButtonBase.Text
                    text: "Bluetooth"
                    onClicked: root.open("devices_other")
                }
            }
        }
    }

    // A card: its icon and title, the button to its whole page, then its rows
    component Card: StyledRect {
        id: card

        required property string icon
        required property string title
        required property string more
        default property alias content: rows.data

        signal open

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: body.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: card.icon
                        color: Colours.palette.m3onSecondaryContainer
                        fill: 1
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.title
                    font: Tokens.font.title.medium
                    elide: Text.ElideRight
                }

                TextButton {
                    type: ButtonBase.Tonal
                    text: card.more
                    onClicked: card.open()
                }
            }

            ColumnLayout {
                id: rows

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2
            }
        }
    }
}
