// Caelestia's colours (its scheme.json, followed live) and fonts (its three in shell.json, the Settings app's Look page)
// for the separate apps: settings, updates, switcher.
// Loaded at run time by each (Loader with this file's path): Quickshell blocks imports from outside a config's folder.
//   c("primary") -> the colour, or its default (Caelestia's dark scheme) until the scheme has loaded or if it lacks it
//   body, title, mono -> the font families (AgrOS's default, JetBrainsMono Nerd Font, where shell.json names none)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var colours: ({})
    readonly property var fallback: ({
            error: "ffb4ab",
            onError: "690005",
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
            surfaceContainerLow: "131419",
            tertiary: "e2bbdb"
        })

    readonly property string defaultFont: "JetBrainsMono Nerd Font"
    property var fonts: ({})
    readonly property string body: fonts.body?.family || defaultFont
    readonly property string title: fonts.title?.family || defaultFont
    readonly property string mono: fonts.mono?.family || defaultFont

    FileView {
        path: `${Quickshell.env("HOME")}/.config/caelestia/shell.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.fonts = JSON.parse(text())?.appearance?.font ?? {};
            } catch (e) {} // half-written while Caelestia saves: the next change reads it
        }
    }

    function c(name: string): color {
        return "#" + (colours[name] ?? fallback[name]);
    }

    FileView {
        id: schemeFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.colours = JSON.parse(text())?.colours ?? {};
            } catch (e) {}
        }
        // Not there yet (a new account's first login, before Caelestia writes it): a missing file isn't watched, so the
        // switcher, up all session, kept the default colours. Read again until it's there (not made: it's Caelestia's)
        onLoadFailed: retry.start()
    }
    Timer {
        id: retry

        interval: 10000
        onTriggered: schemeFile.reload()
    }
}
