// Caelestia's colours (its scheme.json, followed live) for the separate apps: settings, updates, switcher.
// Loaded at run time by each (Loader with this file's path): Quickshell blocks imports from outside a config's folder.
//   c("primary") -> the colour, or its default (Caelestia's dark scheme) until the scheme has loaded or if it lacks it
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var colours: ({})
    readonly property var fallback: ({
            error: "f97386",
            errorContainer: "8c1d18",
            onErrorContainer: "f9dedc",
            onPrimary: "373e61",
            onPrimaryContainer: "dee1ff",
            onSecondaryContainer: "dfe1fa",
            onSurface: "e5e4f0",
            onSurfaceVariant: "aaaab5",
            outline: "8f909a",
            outlineVariant: "464750",
            primary: "bdc4ee",
            primaryContainer: "495074",
            primaryFixed: "cbd2fd",
            secondaryContainer: "3c4058",
            surface: "0d0e12",
            surfaceContainer: "181920",
            surfaceContainerHigh: "1e1f26",
            surfaceContainerHighest: "24252e",
            surfaceContainerLow: "131419"
        })

    function c(name: string): color {
        return "#" + (colours[name] ?? fallback[name]);
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.colours = JSON.parse(text())?.colours ?? {};
            } catch (e) {}
        }
    }
}
