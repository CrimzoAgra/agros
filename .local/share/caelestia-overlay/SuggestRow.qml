pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// A settings row with a text field and suggestions under it as you type (caelestia-overlay: the weather location and
// the time zone on the Language & region page). Up/Down pick a suggestion, Enter or a click takes it (Enter with none
// picked: what's typed), Escape closes them, then puts the value back.
//   value: what the field shows while it isn't being typed in (it follows it)
//   suggestions: [{ text, subtext }] for what's typed; ready: they're for what's typed now (an older list isn't picked)
//   typed(text): the text changed (ask for suggestions); accepted(text, index): Enter or a click (index -1: none)
ColumnLayout {
    id: root

    property string label
    property string subtext
    property string value
    property string placeholderText
    property string icon: "location_on"
    property var suggestions: []
    property bool ready: true
    property bool first: true
    property bool last: true
    property int picked: -1
    property bool dismissed // (Escape: closed until the next key)
    readonly property bool showing: field.activeFocus && ready && !dismissed && suggestions.length > 0

    signal typed(text: string)
    signal accepted(text: string, index: int)

    function accept(index: int): void {
        root.accepted(field.text, index);
        field.focus = false;
    }

    onSuggestionsChanged: picked = -1 // (a new list: no pick carried over to whichever place sits at that row now)
    onValueChanged: if (!field.activeFocus) field.text = value
    Component.onCompleted: field.text = value

    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall / 2

    ConnectedRect {
        Layout.fillWidth: true
        first: root.first
        last: root.last && !root.showing
        implicitHeight: row.implicitHeight + Tokens.padding.medium + Math.max(0, Tokens.padding.large - field.verticalPadding) * 2

        RowLayout {
            id: row

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.label
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtext
                    text: root.subtext
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }

            StyledTextField {
                id: field

                Layout.preferredWidth: Tokens.sizes.nexus.textFieldWidth
                Layout.maximumWidth: root.width / 2
                Layout.alignment: Qt.AlignVCenter
                verticalPadding: Tokens.padding.small
                placeholderText: root.placeholderText

                onTextEdited: {
                    root.dismissed = false;
                    root.typed(text);
                }
                // (left without Enter: back to the value)
                onActiveFocusChanged: if (!activeFocus) text = root.value
                Keys.onReturnPressed: root.accept(root.showing ? root.picked : -1)
                Keys.onEnterPressed: root.accept(root.showing ? root.picked : -1)
                Keys.onEscapePressed: root.showing ? root.dismissed = true : field.focus = false
                Keys.onDownPressed: if (root.showing) root.picked = Math.min(root.picked + 1, root.suggestions.length - 1)
                Keys.onUpPressed: if (root.showing) root.picked = Math.max(root.picked - 1, -1)
            }
        }
    }

    Repeater {
        model: root.showing ? root.suggestions : []

        RowButton {
            required property var modelData
            required property int index

            last: root.last && index === root.suggestions.length - 1
            icon: root.icon
            text: modelData.text
            subtext: modelData.subtext ?? ""
            color: index === root.picked ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
            onClicked: root.accept(index)
        }
    }
}
