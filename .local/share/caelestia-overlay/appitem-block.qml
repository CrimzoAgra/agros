
    // ---- caelestia-overlay: hover an app for favourite (heart) and dock pin (thumbtack) buttons ----
    property var dockPins: []
    readonly property string appId: root.modelData?.id ?? ""
    readonly property bool menuPinned: appId !== "" && Strings.testRegexList(GlobalConfig.launcher.favouriteApps, appId)
    readonly property real pinButtonsWidth: pinButtons.width - Tokens.padding.extraSmall
    // The pin as stored: an older name for the app counts too (as the dock matches them)
    readonly property string dockPin: dockPins.find(p => p === appId || (DesktopEntries.byId(p) ?? DesktopEntries.heuristicLookup(p))?.id === appId) ?? ""
    readonly property bool dockPinned: appId !== "" && dockPin !== ""

    function toggleMenuPin(): void {
        const apps = GlobalConfig.launcher.favouriteApps;
        GlobalConfig.launcher.favouriteApps = menuPinned ? apps.filter(a => !Strings.testRegexList([a], appId)) : [...apps, appId]; // patterns too
    }

    function toggleDockPin(): void {
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-pin`, "dock", dockPin || appId]);
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.config/quickshell/sidedock/pins.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const pins = JSON.parse(text());
                root.dockPins = Array.isArray(pins) ? pins : []; // (a hand edit that isn't a list: no pins, not a dock that errors)
            } catch (e) {}
        }
    }

    HoverHandler {
        id: rowHover
    }

    // The buttons below replace the plain heart
    Binding {
        target: favouriteIcon
        property: "visible"
        value: false
    }

    // Keep the description text clear of both buttons
    Binding {
        target: favouriteIcon
        property: "width"
        value: root.pinButtonsWidth
    }

    Row {
        id: pinButtons

        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.medium - Tokens.padding.extraSmall
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        PinButton {
            id: dockBtn

            icon: "push_pin"
            active: root.dockPinned
            tip: root.dockPinned ? qsTr("Unpin from dock") : qsTr("Pin to dock")
            onClicked: root.toggleDockPin()
        }

        PinButton {
            id: favBtn

            icon: "favorite"
            active: root.menuPinned
            tip: root.menuPinned ? qsTr("Remove from favourites") : qsTr("Add to favourites")
            onClicked: root.toggleMenuPin()
        }
    }

    // Helper label for the hovered button, shown to the left of the buttons
    StyledRect {
        readonly property bool shown: dockBtn.hovered || favBtn.hovered

        anchors.right: pinButtons.left
        anchors.rightMargin: Tokens.spacing.small
        anchors.verticalCenter: parent.verticalCenter
        z: 10

        implicitWidth: tipText.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: tipText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: Colours.palette.m3inverseSurface

        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.9
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }

        StyledText {
            id: tipText

            anchors.centerIn: parent
            text: dockBtn.hovered ? dockBtn.tip : favBtn.tip
            font: Tokens.font.body.small
            color: Colours.palette.m3inverseOnSurface
        }
    }

    component PinButton: Item {
        id: btn

        required property string icon
        required property bool active
        required property string tip

        readonly property alias hovered: btnHover.hovered

        signal clicked

        implicitWidth: btnIcon.implicitHeight + Tokens.padding.small * 2
        implicitHeight: implicitWidth

        // Shown on hover of the app; when not hovered, only the active ones stay visible
        opacity: rowHover.hovered || active ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StateLayer {
            radius: Tokens.rounding.full
            disabled: !rowHover.hovered
            onClicked: btn.clicked()
        }

        MaterialIcon {
            id: btnIcon

            anchors.centerIn: parent
            text: btn.icon
            fill: btn.active ? 1 : 0
            color: btn.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        HoverHandler {
            id: btnHover
        }
    }
}
