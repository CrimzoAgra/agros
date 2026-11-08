import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

// Caps, Num and Scroll Lock icons (caelestia-overlay: Caelestia's own has only Caps and Num Lock)
ColumnLayout {
    id: root

    required property color colour
    required property int parentSpacing

    spacing: 0

    LockIcon {
        on: Hypr.capsLock
        icon: "keyboard_capslock_badge"
        gapAbove: false
    }

    LockIcon {
        on: Hypr.numLock
        icon: "looks_one"
        gapAbove: Hypr.capsLock
    }

    LockIcon {
        on: ScrollLock.on
        icon: "square"  // no Material badge for S: a filled square like the others with an S cut out
        letter: "S"
        gapAbove: Hypr.capsLock || Hypr.numLock
    }

    component LockIcon: Item {
        id: item

        required property bool on
        required property string icon
        required property bool gapAbove
        property string letter
        property real size: on ? lockIcon.implicitHeight + (gapAbove ? root.parentSpacing : 0) : 0

        implicitWidth: lockIcon.implicitWidth
        implicitHeight: Math.round(size)

        Behavior on size {
            Anim {
                type: Anim.SlowEffects
            }
        }

        MaterialIcon {
            id: lockIcon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            scale: item.on ? 1 : 0.5
            opacity: item.on ? 1 : 0

            text: item.icon
            color: root.colour
            fill: 1
            grade: 25

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {}
            }

            StyledText {
                visible: !!item.letter
                anchors.centerIn: parent
                text: item.letter
                color: Colours.palette.m3surfaceContainer
                renderType: Text.NativeRendering  // hinted onto the pixel grid: crisp like the 1 in Num Lock's badge
                font.pixelSize: Math.round(lockIcon.implicitHeight * 0.5)
                font.weight: Font.Bold
            }
        }
    }
}
