        // ---- caelestia-overlay: the weather location, the desktop forecast widget's own picker (both load
        // ~/.config/quickshell/common/PlacePicker.qml and set the same setting: a change in one shows in the other) ----
        SuggestRow {
            id: weatherLocation

            readonly property var places: placesLoader.item

            label: Tr.tr("Location")
            subtext: Tr.tr("Here and on the desktop forecast. Empty: automatic")
            placeholderText: Tr.tr("Automatic")
            value: places?.name ?? ""
            ready: places?.suggestedFor === typedText
            suggestions: (places?.suggestions ?? []).map(p => ({
                        text: p.name,
                        subtext: [p.admin1 !== p.name ? p.admin1 : "", p.country].filter(s => s).join(", ")
                    }))
            onTyped: t => {
                typedText = t.trim();
                suggestDelay.restart();
            }
            onAccepted: (t, i) => {
                places?.apply(t, i);
                places?.closeSuggestions();
            }

            property string typedText

            Loader {
                id: placesLoader

                visible: false // (no place in the layout: it has nothing to show)
                source: `file://${Quickshell.shellPath("../common/PlacePicker.qml")}`
            }

            // (a quarter second after the last key, as on the desktop)
            Timer {
                id: suggestDelay

                interval: 250
                onTriggered: weatherLocation.places?.suggest(weatherLocation.typedText)
            }
        }
