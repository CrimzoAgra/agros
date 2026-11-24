pragma ComponentBehavior: Bound

// caelestia-overlay: one AgrOS setting as a Nexus row (AgrosSettings.qml's, by its key): its name, what it does (wrapped,
// not cut off as Nexus's own rows cut theirs), and its control: a switch, a row of buttons for a few short choices (a
// menu for more), a spin box for whole numbers (a slider for the rest), a text field. Changes go through
// AgrosSettings.set

import QtQuick
import QtQuick.Layouts
import Quickshell
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
    // (a few short choices: buttons side by side)
    readonly property bool buttons: options.length > 0 && options.length <= 3 && options.reduce((n, o) => n + String(o.label ?? o.value).length, 0) <= 24

    function set(v: var): void {
        if (JSON.stringify(v) !== JSON.stringify(value))
            AgrosSettings.set(key, v);
    }

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + Tokens.padding.medium * 2
    clip: false
    z: menuLoader.item?.expanded ? 1 : 0 // qmllint disable missing-property

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.large

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
                text: root.setting?.description ?? ""
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.Wrap
            }
        }

        // A switch
        StyledSwitch {
            visible: root.type === "bool"
            cLayer: 2
            checked: root.value === true
            onToggled: root.set(checked)
        }

        // A few short choices: a button each, the current one filled
        Row {
            visible: root.type === "choice" && root.buttons
            spacing: Tokens.spacing.extraSmall

            Repeater {
                model: root.type === "choice" && root.buttons ? root.options : []

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

        // More choices: a menu
        Loader {
            id: menuLoader

            active: root.type === "choice" && !root.buttons
            visible: active

            sourceComponent: SplitButton {
                id: split

                type: SplitButton.Tonal
                fallbackText: root.options.find(o => o.value === root.value)?.label ?? String(root.value ?? "")
                menuItems: items.instances
                active: menuItems.find(i => i.value === root.value) ?? null
                stateLayer.onClicked: split.expanded = !split.expanded
                menu.onItemSelected: item => root.set(item.value)

                Variants {
                    id: items

                    model: root.options

                    MenuItem {
                        required property var modelData

                        text: modelData.label || String(modelData.value) || "None"
                        value: modelData.value
                    }
                }
            }
        }

        // A whole number
        StyledSpinBox {
            visible: root.type === "number" && root.setting?.integer === true
            cLayer: 2
            from: root.setting?.min ?? 0
            to: root.setting?.max ?? 9999
            stepSize: root.setting?.step ?? 1
            value: typeof root.value === "number" ? root.value : 0
            onValueModified: root.set(Math.round(value))
        }

        // Any other number: a slider, set when let go
        RowLayout {
            visible: root.type === "number" && root.setting?.integer !== true
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

        // Text: set when done (Enter, or the field left); one that doesn't fit the setting's pattern isn't
        StyledTextField {
            id: field

            readonly property bool fits: !root.setting?.pattern || new RegExp(`^(?:${root.setting.pattern})$`).test(text)

            visible: root.type === "text"
            Layout.preferredWidth: 220
            text: typeof root.value === "string" ? root.value : ""
            placeholderText: root.setting?.placeholder ?? ""
            onEditingFinished: if (fits) root.set(text)
        }
    }
}
