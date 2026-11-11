// The weather location picker's workings, one for the desktop forecast widget (widgets/) and Caelestia's settings
// (Nexus > Language & region, caelestia-overlay's nexus_location), each with its own look. Both set Caelestia's own
// setting (services.weatherLocation in ~/.config/caelestia/shell.json, which Caelestia's weather follows too), so a
// change in one shows in the other. Loaded at run time by each (Loader with this file's path): Quickshell blocks imports
// from outside a config's folder.
//   location: the setting (a city name, "lat,lon" for a place picked from the suggestions, "" for automatic by IP)
//   name: what to show for it (a picked place's name, not its coordinates)
//   suggest(text) / suggestions / suggestedFor / closeSuggestions(): open-meteo's towns for what's typed
//   apply(text, picked): what Enter does (the suggestion picked with the arrow keys, else the text as typed)
//   changed(): the place to show may have changed without the setting (names loaded, a place picked again)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal changed()

    function get(url: string, cb: var): void {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState === XMLHttpRequest.DONE && x.status === 200)
                try {
                    cb(JSON.parse(x.responseText));
                } catch (e) {}
        };
        x.open("GET", url);
        x.send();
    }

    // Caelestia's setting, read from its file (not its internal config module, which an update may rename)
    FileView {
        path: `${Quickshell.env("HOME")}/.config/caelestia/shell.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.location = String(JSON.parse(text()).services?.weatherLocation ?? "").trim();
            } catch (e) {} // half-written while Caelestia saves: the next change reads it
            if (!root.ready) {
                root.ready = true;
                root.changed();
            }
        }
        onLoadFailed: if (!root.ready) {
            root.ready = true; // no settings file: automatic
            root.changed();
        }
    }
    property string location: ""
    property bool ready: false
    readonly property string name: placeNames[location] || location

    // Set (empty: automatic again), in Caelestia's file as it writes it (tried again twice: Caelestia may be halfway
    // through rewriting the file, which jq then can't read). Under the lock caelestia-pin takes to change the same file
    // (its Super menu pins): neither loses the other's change
    function setLocation(loc: string): void {
        Quickshell.execDetached(["sh", "-c", `f="$HOME/.config/caelestia/shell.json"; exec 9>"$f.lock"; flock 9; [ -s "$f" ] || echo "{}" >"$f"; for i in 1 2 3; do jq --indent 4 --arg l "$1" '.services.weatherLocation = $l' "$f" >"$f.tmp" && mv "$f.tmp" "$f" && exit; sleep 0.3; done; rm -f "$f.tmp"`, "sh", loc.trim()]);
    }

    // Places picked from the suggestions are saved as "lat,lon" (the exact place, for Caelestia too); their names are kept
    // here to show, keyed by that value
    FileView {
        id: placeNamesFile

        path: `${Quickshell.env("HOME")}/.local/state/desktop-widgets/place-names.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.placeNames = JSON.parse(text()) ?? {};
            } catch (e) {}
            root.changed();
        }
        // (none yet: made empty and read again, so it's watched; a place picked in the other one then shows here by its
        // name too, not its coordinates)
        onLoadFailed: makeNames.running = true
    }
    Process {
        id: makeNames

        command: ["sh", "-c", '[ -e "$1" ] || { mkdir -p "${1%/*}" && echo "{}" >"$1"; }', "sh", placeNamesFile.path]
        onExited: placeNamesFile.reload()
    }
    property var placeNames: ({})

    // pickPlace(place): an open-meteo geocoding result set as the location, by its coordinates, its name kept
    function pickPlace(p: var): void {
        const loc = `${Number(p.latitude).toFixed(4)},${Number(p.longitude).toFixed(4)}`;
        const names = Object.assign({}, root.placeNames);
        names[loc] = p.name;
        root.placeNames = names;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s\\n" "$2" >"$1.tmp" && mv "$1.tmp" "$1"', "sh", placeNamesFile.path, JSON.stringify(names)]);
        // the place it already is (picked again, maybe under a new name): the setting doesn't change
        if (loc === root.location)
            root.changed();
        else
            root.setLocation(loc);
    }

    // Enter: the suggestion picked (if the list is still for what's typed), else what's typed if it's new
    function apply(text: string, picked: int): void {
        if (picked >= 0 && suggestions[picked] && suggestedFor === text.trim())
            pickPlace(suggestions[picked]);
        else if (text.trim() !== name)
            setLocation(text);
    }

    // Suggestions for the location being typed: open-meteo's geocoding search (nothing else sent with it); a reply to
    // an older text dropped
    property var suggestions: []
    property string suggestedFor // (the text they're for: Up/Down and Enter use them only while it's still what's typed)
    property int suggestId: 0

    function suggest(text: string): void {
        const id = ++root.suggestId;
        const q = text.trim();
        if (q.length < 2) {
            root.suggestions = [];
            return;
        }
        // (more asked than shown: countries, mountains and airports are dropped)
        get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=20&format=json`, g => {
            if (id !== root.suggestId)
                return;
            root.suggestedFor = q;
            root.suggestions = root.towns(g.results).slice(0, 6).map(p => Object.assign({}, p, {
                name: root.townName(p),
                admin1: root.regionName(p.admin1)
            }));
        });
    }

    function closeSuggestions(): void {
        root.suggestId++; // (a reply still on its way: dropped)
        root.suggestions = [];
    }

    // Open-meteo's places (GeoNames) that are towns and cities, the same rule everywhere: its feature code says so
    function towns(results: var): var {
        return (results ?? []).filter(p => String(p.feature_code ?? "").startsWith("PPL"));
    }

    // A region's name without its kind, the same rule for every country: "Porto District", "Moscow Oblast", "Canton of
    // Bern", "Departamento de Bolívar", "Jakarta Special Capital Region" are Porto, Moscow, Bern, Bolívar, Jakarta. A name
    // that's only directions or kinds without it stays whole ("Western Province", "National Capital Region", "Free State")
    function regionName(s: var): string {
        const n = String(s ?? "").trim();
        const kind = "(Special )?Capital Region|Capital Territory|Special Region|Autonomous (Region|Okrug|Oblast|Republic|Community)|Province|Region|Department|Oblast|District|County|Governorate|State|Division|Parish|Rayon|Raion|Prefecture|Municipality|Voivodeship|Canton|Territory|Krai|Kray|Okrug|Republic|Emirate|Borough";
        const m = n.replace(new RegExp(`\\s+(${kind})$`), "")
            .replace(new RegExp(`^(National Capital Territory|Special Region|Autonomous Region|Provincia|Departamento|Province|Canton|State|Region|Republic|Municipality|Governorate|Distrito|District) (of|in|de|del|da|do|di|du) `), "")
            .replace(/^(Provincia|Departamento|Distrito|Canton) (?=[A-ZÀ-Ý])/, "");
        const generic = /^(North|South|East|West|Northern|Southern|Eastern|Western|Central|Capital|National|Upper|Lower|Free|Federal|Autonomous|Special|Greater|Middle|Inner|Outer|Coastal|Far|Grand|Northeast|Northwest|Southeast|Southwest|North-East|North-West|South-East|South-West)$/;
        return m && m !== n && !m.split(/\s+/).every(w => generic.test(w)) ? m : n;
    }

    // A town's name as people say it. GeoNames sometimes names an area's seat by the area: "Matosinhos Municipality",
    // "Querétaro City". So the seat (PPLA*, PPLC) of an area of its name plus one word (in any language) is named as the
    // area; "Frankfurt am Main", "Santiago de los Caballeros" and a city's parts ("Stuttgart Feuerbach") keep theirs
    function townName(p: var): string {
        const n = String(p.name ?? "");
        if (!/^PPL(A\d?|C)$/.test(String(p.feature_code ?? "")))
            return n;
        for (const a of [p.admin4, p.admin3, p.admin2].map(s => String(s ?? "")))
            if (a && (n.startsWith(a + " ") || n.endsWith(" " + a)) && n.replace(a, "").trim().split(/\s+/).length === 1)
                return a;
        return n;
    }

    // "City, region, country", the parts it has (a region named as the city left out)
    function placeLabel(p: var): string {
        return [p.name, p.admin1 !== p.name ? p.admin1 : "", p.country].filter(s => s).join(", ");
    }
}
