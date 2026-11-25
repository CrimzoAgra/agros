pragma ComponentBehavior: Bound

// caelestia-overlay: one AgrOS setting as a Nexus row (AgrosSettings.qml's, by its key): its name, what it does (wrapped,
// not cut off as Nexus's own rows cut theirs), and its control: a switch, a row of buttons for a few short choices (a
// menu for more), a spin box for whole numbers (a slider for the rest), a text field, shortcuts as chips with + to
// record one; an app started at login with its icon, how it starts and a button removing it; pictures to pick one from
// (a wallpaper) under it. Many choices (310 fonts): a list to search under the row, made when opened, only the lines in
// sight drawn (a menu of every font, for each of three rows, froze Nexus for seconds; Caelestia's menus don't scroll).
// Only its own control is made (a page of 100 rows, each with every kind of control hidden, took seconds to show).
// Changes go through AgrosSettings.set

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    required property string key
    readonly property var setting: AgrosSettings.byKey[key] ?? null
    readonly property string type: setting?.type ?? ""
    readonly property var value: setting?.value
    readonly property var options: setting?.options ?? []
    // (a few short choices: buttons side by side; many (fonts, apps): a list to search, opened under the row)
    readonly property bool buttons: options.length > 0 && options.length <= 3 && options.reduce((n, o) => n + String(o.label ?? o.value).length, 0) <= 24
    readonly property bool long: options.length > 8
    readonly property string current: options.find(o => o.value === value)?.label || String(value ?? "")
    property bool listOpen
    // (Caelestia's options with no description of their own have their path as one: not shown)
    readonly property string description: /\s/.test(setting?.description ?? "") ? setting.description : ""

    function set(v: var): void {
        if (JSON.stringify(v) !== JSON.stringify(value))
            AgrosSettings.set(key, v);
    }

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Tokens.padding.medium * 2
    clip: false
    z: control.item?.expanded ? 1 : 0 // qmllint disable missing-property

    ColumnLayout {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        // Its name and its control side by side; the control under the name when that would leave the name too little
        // room (a narrow page, a card on Nexus's Home)
        GridLayout {
            id: row

            readonly property bool stacked: width > 0 && Math.min(control.implicitWidth, 340) > width - 200

            Layout.fillWidth: true
            columns: stacked ? 1 : 3
            columnSpacing: Tokens.spacing.large
            rowSpacing: Tokens.spacing.medium

            IconImage {
                visible: root.type === "startup"
                implicitSize: 32
                source: visible ? Quickshell.iconPath(root.setting?.icon ?? "", "application-x-executable") : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.setting?.label ?? root.key
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.description
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }

                // (a shortcut another action has too)
                StyledText {
                    readonly property var others: {
                        const out = [];
                        if (root.type === "keys" && !root.setting?.modifier)
                            for (const k of Array.from(root.value ?? []))
                                for (const l of AgrosSettings.usage[AgrosSettings.norm(k)] ?? [])
                                    if (l !== root.setting?.label && !out.includes(l))
                                        out.push(l);
                        return out;
                    }

                    Layout.fillWidth: true
                    visible: others.length > 0
                    text: "Also used by: " + others.join(", ")
                    color: Colours.palette.m3error
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
            }

            Loader {
                id: control

                Layout.maximumWidth: root.type === "keys" ? 340 : Number.POSITIVE_INFINITY
                visible: !!sourceComponent
                sourceComponent: ({
                        bool: switchC,
                        choice: root.buttons ? buttonsC : root.long ? pickC : menuC,
                        startup: startupC,
                        keys: keysC,
                        number: root.setting?.integer === true ? spinC : sliderC,
                        text: fieldC
                    })[root.type] ?? null
            }
        }

        // Many choices: the list, open
        Loader {
            Layout.fillWidth: true
            active: root.listOpen
            visible: active
            sourceComponent: listC
        }

        // Pictures: the one set outlined
        Loader {
            Layout.fillWidth: true
            active: root.type === "image"
            visible: active
            sourceComponent: picturesC
        }
    }

    // A switch
    Component {
        id: switchC

        StyledSwitch {
            cLayer: 2
            checked: root.value === true
            onToggled: root.set(checked)
        }
    }

    // A few short choices: a button each, the current one filled
    Component {
        id: buttonsC

        Row {
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.options

                TextButton {
                    required property var modelData

                    type: ButtonBase.Tonal
                    isToggle: true
                    checked: root.value === modelData.value
                    text: modelData.label ?? String(modelData.value)
                    horizontalPadding: Tokens.padding.large
                    verticalPadding: Tokens.padding.small
                    onClicked: root.set(modelData.value)
                }
            }
        }
    }

    // More choices: a menu
    Component {
        id: menuC

        SplitButton {
            id: split

            type: SplitButton.Tonal
            fallbackText: root.options.find(o => o.value === root.value)?.label ?? String(root.value ?? "")
            menuItems: items.instances
            active: menuItems.find(i => i.value === root.value) ?? null
            stateLayer.onClicked: split.expanded = !split.expanded
            menu.onItemSelected: item => root.set(item.value)

            Variants {
                id: items

                // (made when opened: each one is a row of the menu)
                model: split.expanded ? root.options : []

                MenuItem {
                    required property var modelData

                    text: modelData.label || String(modelData.value) || "None"
                    value: modelData.value
                }
            }
        }
    }

    // Many choices: the one set, and the list under the row (opened, closed)
    Component {
        id: pickC

        TextButton {
            type: ButtonBase.Tonal
            text: `${root.current || "None"}  ${root.listOpen ? "▴" : "▾"}`
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.small
            onClicked: root.listOpen = !root.listOpen
        }
    }

    Component {
        id: listC

        ColumnLayout {
            spacing: Tokens.spacing.small

            StyledTextField {
                id: search

                Layout.fillWidth: true
                placeholderText: "Search"
                Component.onCompleted: forceActiveFocus()
                Keys.onEscapePressed: root.listOpen = false
                onAccepted: if (list.count) list.itemAtIndex(0)?.pick() // qmllint disable missing-property
            }

            ListView {
                id: list

                // (a font's name in that font: its row says how it looks)
                readonly property bool fonts: /\.family$/.test(root.key)

                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 300)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: {
                    const q = search.text.trim().toLowerCase();
                    return q ? root.options.filter(o => String(o.label || o.value).toLowerCase().includes(q)) : root.options;
                }
                Component.onCompleted: positionViewAtIndex(Math.max(0, root.options.findIndex(o => o.value === root.value)), ListView.Center)

                delegate: StyledRect {
                    id: line

                    required property var modelData
                    readonly property bool selected: modelData.value === root.value

                    function pick(): void {
                        root.set(modelData.value);
                        root.listOpen = false;
                    }

                    width: ListView.view.width
                    implicitHeight: lineText.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.small
                    color: Qt.alpha(Colours.palette.m3tertiaryContainer, selected ? 1 : 0)

                    StyledText {
                        id: lineText

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        text: line.modelData.label || String(line.modelData.value) || "None"
                        font.family: list.fonts && line.modelData.value ? line.modelData.value : Tokens.font.body.small.family
                        font.pointSize: Tokens.font.body.small.pointSize
                        color: line.selected ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: line.radius
                        onClicked: line.pick()
                    }
                }
            }
        }
    }

    // An app started at login: how it starts, and no more
    Component {
        id: startupC

        Row {
            spacing: Tokens.spacing.small

            Loader {
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: buttonsC
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "delete"
                type: IconButton.Text
                onClicked: root.set("removed")
            }
        }
    }

    // Shortcuts: each one a chip (red when another action has it too; x on hover takes it off), + records one more
    Component {
        id: keysC

        Flow {
            layoutDirection: Qt.RightToLeft
            spacing: Tokens.spacing.extraSmall

            IconButton {
                id: add

                visible: !root.setting?.readonly && (!root.setting?.modifier || (root.value ?? []).length === 0)
                icon: "add"
                type: IconButton.Tonal
                onClicked: AgrosSettings.startCapture(root.key, !!root.setting?.modifier)
            }

            Repeater {
                model: root.value ?? []

                StyledRect {
                    id: chip

                    required property string modelData
                    readonly property bool clash: !root.setting?.modifier && (AgrosSettings.usage[AgrosSettings.norm(modelData)] ?? []).length > 1

                    implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: add.implicitHeight
                    radius: Tokens.rounding.small
                    color: clash ? Colours.palette.m3errorContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                    HoverHandler {
                        id: chipHover
                    }

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: AgrosSettings.pretty(chip.modelData)
                            font: Tokens.font.mono.small
                            color: chip.clash ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
                        }

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chipHover.hovered && !root.setting?.readonly
                            text: "close"

                            TapHandler {
                                onTapped: root.set(Array.from(root.value ?? []).filter(k => k !== chip.modelData))
                            }
                        }
                    }
                }
            }
        }
    }

    // A whole number
    Component {
        id: spinC

        StyledSpinBox {
            cLayer: 2
            from: root.setting?.min ?? 0
            to: root.setting?.max ?? 9999
            stepSize: root.setting?.step ?? 1
            value: typeof root.value === "number" ? root.value : 0
            onValueModified: root.set(Math.round(value))
        }
    }

    // Any other number: a slider, set when let go
    Component {
        id: sliderC

        RowLayout {
            spacing: Tokens.spacing.medium

            StyledSlider {
                id: slider

                Layout.preferredWidth: 180
                from: root.setting?.min ?? 0
                to: root.setting?.max ?? 1
                stepSize: root.setting?.step ?? 0
                value: typeof root.value === "number" ? root.value : 0
                onPressedChanged: if (!pressed) root.set(Math.round(value * 1000) / 1000)
            }

            StyledText {
                Layout.preferredWidth: 44
                text: (Math.round(slider.value * 100) / 100).toString()
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // Text: set when done (Enter, or the field left); one that doesn't fit the setting's pattern isn't
    Component {
        id: fieldC

        StyledTextField {
            readonly property bool fits: !root.setting?.pattern || new RegExp(`^(?:${root.setting.pattern})$`).test(text)

            implicitWidth: 220
            text: typeof root.value === "string" ? root.value : ""
            placeholderText: root.setting?.placeholder ?? ""
            onEditingFinished: if (fits) root.set(text)
        }
    }

    // Pictures: the one set outlined
    Component {
        id: picturesC

        GridLayout {
            columns: Math.max(2, Math.floor(width / 150))
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            Repeater {
                model: root.options

                StyledClippingRect {
                    id: pic

                    required property var modelData
                    readonly property bool selected: modelData.value === root.value

                    Layout.fillWidth: true
                    implicitHeight: width * 9 / 16
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainerHigh

                    // (no picture: "Same as the others", this screen's left to the one for every screen)
                    StyledText {
                        visible: !pic.modelData.value
                        anchors.centerIn: parent
                        width: parent.width - Tokens.padding.medium * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: pic.modelData.label ?? ""
                        font: Tokens.font.label.medium
                    }

                    Image {
                        visible: !!pic.modelData.value
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 300
                        source: pic.modelData.value ? "file://" + pic.modelData.value.split("/").map(encodeURIComponent).join("/") : ""
                    }

                    StyledRect {
                        anchors.fill: parent
                        color: "transparent"
                        radius: pic.radius
                        border.width: pic.selected ? 3 : 0
                        border.color: Colours.palette.m3primary
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: pic.radius
                        onClicked: if (!pic.selected) root.set(pic.modelData.value)
                    }
                }
            }
        }
    }
}
