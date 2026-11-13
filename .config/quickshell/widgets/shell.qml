// Desktop widgets in the style of the wallpaper: Miles' leap of faith from Into the Spider-Verse.
// Comic panels with hard offset shadows and halftone dots, yellow narration captions, Bangers lettering,
// and the film's red/cyan misprint that glitches now and then.
// Colours are picked from the wallpaper (ink navy, sky purple, spire cyan, sign magenta, Miles' red),
// not from Caelestia's scheme, so they stay fixed when the scheme changes.
// Laid out around the falling figure: the two columns sit in the open sky left and right of it, on a 1920x1080
// stage scaled and centred like the wallpaper, so they stay put around him on any size or shape of screen.
// Separate from Caelestia, so Caelestia updates don't touch it.
// Blur behind the panels comes from the "desktop-widgets" layer rule in ~/.config/caelestia/user/desktop.lua.
// Kept alive on purpose: the widgets keep updating (stats, weather, clock, media) even while windows cover them,
// so they're current the moment the desktop shows. Don't pause them when hidden.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")

    readonly property color ink: "#0c1124"
    readonly property color sky: "#514dbd"
    readonly property color cyan: "#3df2ff"
    readonly property color magenta: "#ff3dbb"
    readonly property color red: "#ff2d4a"
    readonly property color yellow: "#ffe45c"
    readonly property color paper: "#f4f0ff"

    readonly property string comic: "Bangers"
    readonly property string mono: "CaskaydiaCove NF"
    readonly property string icons: "Material Symbols Rounded"

    // Narration under the falling figure, a new line every hour
    readonly property var lines: ["It's a leap of faith.", "Anyone can wear the mask.", "What's up, danger?", "Alright, let's do this one last time.", "You're gonna be okay."]

    // ---- System stats ----
    property real cpu: 0
    property real ram: 0
    property real ramUsedGb: 0
    property real disk: 0
    property string diskText: ""
    property int cpuTemp: 0
    property real gpu: -1
    property int gpuTemp: 0
    property real netDown: 0
    property real netUp: 0
    property string uptime: ""
    property var lastCpu: null
    property var lastNet: null
    readonly property bool tingling: cpu > 0.85 || cpuTemp >= 85 || gpuTemp >= 83

    function human(bytesPerSec: real): string {
        if (bytesPerSec >= 1e6)
            return (bytesPerSec / 1e6).toFixed(1) + " MB/s";
        return Math.round(bytesPerSec / 1e3) + " kB/s";
    }

    FileView {
        id: stat

        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu && total > root.lastCpu.total)
                root.cpu = 1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total);
            root.lastCpu = { idle, total };
        }
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        onLoaded: {
            const m = {};
            for (const l of text().split("\n")) {
                const p = l.split(/:\s+/);
                m[p[0]] = parseInt(p[1]);
            }
            root.ram = 1 - m.MemAvailable / m.MemTotal;
            root.ramUsedGb = (m.MemTotal - m.MemAvailable) / 1048576;
        }
    }

    FileView {
        id: netdev

        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            // Wired, Wi-Fi and mobile links only (en*, eth*, wl*, ww*): a VPN's tunnel (Proton VPN's proton0, wg*, tun*)
            // carries the same traffic as the link under it, which then counted twice; bridges and containers' veths too
            for (const l of text().split("\n").slice(2)) {
                const p = l.trim().split(/[:\s]+/);
                if (p.length < 10 || !/^(en|eth|wl|ww)/.test(p[0]))
                    continue;
                rx += Number(p[1]);
                tx += Number(p[9]);
            }
            const now = Date.now();
            if (root.lastNet) {
                const dt = (now - root.lastNet.t) / 1000;
                root.netDown = Math.max(0, (rx - root.lastNet.rx) / dt);
                root.netUp = Math.max(0, (tx - root.lastNet.tx) / dt);
            }
            root.lastNet = { rx, tx, t: now };
        }
    }

    FileView {
        id: uptimeFile

        path: "/proc/uptime"
        onLoaded: {
            const s = parseFloat(text());
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            root.uptime = (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
        }
    }

    // CPU temperature: k10temp or zenpower (AMD), coretemp (Intel), cpu_thermal (ARM); hwmon numbers change between
    // boots. None of them (a VM): no temperature shown
    FileView {
        id: tempFile

        onLoaded: root.cpuTemp = Math.round(parseInt(text()) / 1000)
    }

    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name 2>/dev/null) in k10temp|zenpower|coretemp|cpu_thermal) echo $h/temp1_input; exit;; esac; done"]
        stdout: StdioCollector {
            onStreamFinished: tempFile.path = text.trim()
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
            uptimeFile.reload();
            if (tempFile.path)
                tempFile.reload();
        }
    }

    // One long-running nvidia-smi instead of spawning one every few seconds. Only when the NVIDIA card drives a
    // screen: on a laptop that shows the desktop on its other GPU, asking every 2 s would keep the NVIDIA card awake
    // and drain the battery. Looked for again every 10 s until there is one (a screen plugged in later), and every
    // minute while there is (unplugged: nvidia-smi stopped, the meter hidden); not at all without NVIDIA's driver
    Process {
        running: true
        command: ["sh", "-c", "[ -d /sys/module/nvidia ] || exit 0; while :; do on=; for s in /sys/class/drm/card*-*/status; do c=${s%/*}; c=${c##*/}; [ \"$(cat \"$s\")\" = connected ] && [ \"$(basename \"$(readlink /sys/class/drm/${c%%-*}/device/driver)\")\" = nvidia ] && on=1; done; if [ -n \"$on\" ]; then timeout 60 nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits -l 2; [ $? = 124 ] && continue; fi; echo off; sleep 10; done"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "off") {
                    root.gpu = -1;
                    root.gpuTemp = 0; // (its last heat would keep the stats tingling)
                    return;
                }
                const [u, t] = line.split(",").map(s => parseInt(s));
                if (!isNaN(u)) {
                    root.gpu = u / 100;
                    root.gpuTemp = t;
                }
            }
        }
    }

    Process {
        id: df

        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [used, size] = text.trim().split("\n")[1].trim().split(/\s+/).map(Number);
                root.disk = used / size;
                root.diskText = Math.round(used / 1e9) + "/" + Math.round(size / 1e9) + " GB";
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }

    // ---- Weather (same sources as Caelestia's: ip-api for the location, open-meteo for the forecast) ----
    property var weather: null
    property string city: ""

    // Caelestia's settings this uses, read from its file (not its internal config module, which an update may rename):
    // its defaults where the file has none
    FileView {
        id: caelestiaConfig

        path: `${Quickshell.env("HOME")}/.config/caelestia/shell.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.services = JSON.parse(text()).services ?? {};
            } catch (e) {} // half-written while Caelestia saves: the next change reads it
        }
    }
    property var services: ({})

    // The weather location and its picker: the one Caelestia's settings use too (../common/PlacePicker.qml; not an
    // import: Quickshell blocks those from outside this folder). Its setting is Caelestia's, so a change in either shows
    // in both
    Loader {
        id: placesLoader
        source: `file://${Quickshell.shellPath("../common/PlacePicker.qml")}`
    }
    readonly property var places: placesLoader.item
    readonly property string location: places?.location ?? ""

    function get(url: string, cb: var): void {
        places?.get(url, cb);
    }

    onLocationChanged: if (places?.ready) fetchWeather()
    // (the first fetch once the setting is known; again when the place's name may have changed)
    Connections {
        target: root.places

        function onChanged(): void {
            root.fetchWeather();
        }
    }

    // Bumped on every fetch: replies to an older one (e.g. the previous location) are dropped
    property int fetchId: 0

    function fetchForecast(id: int, name: string, lat: real, lon: real): void {
        get(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=4`, w => {
            if (id !== root.fetchId)
                return;
            root.city = name;
            root.weather = w;
        });
    }

    function fetchWeather(): void {
        const id = ++root.fetchId;
        const loc = root.location;
        const coords = loc.split(",").map(s => parseFloat(s));
        if (coords.length === 2 && coords.every(n => !isNaN(n))) {
            // (a place picked from the suggestions: by the name it had there)
            fetchForecast(id, root.places.name, coords[0], coords[1]);
        } else if (loc) {
            get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(loc)}&count=10&format=json`, g => {
                // the first town of that name ("Roma" is the town, not Romania), else what there is
                const r = root.places.towns(g.results)[0] ?? g.results?.[0];
                // No such place (misspelt): said so, not the previous city's forecast left showing
                if (!r) {
                    if (id === root.fetchId) {
                        root.city = loc + " ?";
                        root.weather = null;
                    }
                    return;
                }
                // The top match is the right place but may be named "... Municipality": show the name as typed
                fetchForecast(id, loc, r.latitude, r.longitude);
            });
        } else {
            get("http://ip-api.com/json?fields=status,city,lat,lon", ip => {
                if (ip.status !== "success")
                    return;
                fetchForecast(id, ip.city, ip.lat, ip.lon);
            });
        }
    }

    function weatherIcon(code: int, day: bool): string {
        if (code <= 1)
            return day ? "clear_day" : "clear_night";
        if (code === 2)
            return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (code === 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "foggy";
        if (code >= 95)
            return "thunderstorm";
        if (code >= 71 && code <= 77 || code === 85 || code === 86)
            return "weather_snowy";
        return "rainy";
    }

    function weatherText(code: int): string {
        return ({ 0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast", 45: "Fog", 48: "Fog",
                  51: "Drizzle", 53: "Drizzle", 55: "Drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
                  61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
                  71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow", 80: "Showers", 81: "Showers",
                  82: "Heavy showers", 85: "Snow showers", 86: "Snow showers", 95: "Thunderstorm",
                  96: "Thunderstorm", 99: "Thunderstorm" })[code] ?? "—";
    }

    // At login the network or the VPN may not be up yet: fetch again on each network change (NetworkManager's
    // events) until the first forecast arrives
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            // (once the events settle: a reconnect prints 10-20 lines, each was a request to ip-api, rate-limited)
            onRead: if (!root.weather) netSettle.restart()
        }
    }
    Timer {
        id: netSettle

        interval: 3000
        onTriggered: root.fetchWeather()
    }

    Timer {
        interval: 30 * 60000
        running: true
        repeat: true
        onTriggered: root.fetchWeather()
    }

    // ---- Media: the same player as Caelestia's dashboard (its default player, else the first one) ----
    // Not Capri's: Electron gives every app a media player (org.mpris.MediaPlayer2.chromium.instance<pid>, identity
    // "Capri Desktop"), and with Spotify closed hers, with nothing playing, took the widget
    readonly property var players: Mpris.players.values.filter(p => !/^capri/i.test(p.identity ?? ""))
    readonly property var playerAliases: services.playerAliases ?? [{ from: "com.github.th_ch.youtube_music", to: "YT Music" }]
    readonly property string defaultPlayer: services.defaultPlayer ?? "Spotify"
    readonly property MprisPlayer player: root.players.find(p => (root.playerAliases.find(a => a.from === p.identity)?.to ?? p.identity) === root.defaultPlayer) ?? root.players[0] ?? null

    Timer {
        interval: 1000
        running: root.player?.isPlaying ?? false
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

    // ---- Building blocks ----

    // Halftone dots, biggest in the top-right corner and fading out from it
    component Halftone: Canvas {
        id: tone

        property color dot: root.cyan
        property real step: 9

        onDotChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d");
            g.reset();
            g.fillStyle = dot;
            const diag = Math.hypot(width, height);
            for (let y = 0, row = 0; y < height + step; y += step * 0.87, row++)
                for (let x = row % 2 ? step / 2 : 0; x < width + step; x += step) {
                    const r = step * 0.48 * (1 - Math.hypot(width - x, y) / diag) ** 2;
                    if (r < 0.4)
                        continue;
                    g.beginPath();
                    g.arc(x, y, r, 0, Math.PI * 2);
                    g.fill();
                }
        }
    }

    // Text printed slightly off-register in cyan and magenta, like the film; glitch() shakes it
    component Misprint: Item {
        id: mp

        property string text
        property int size: 40
        property color colour: root.paper
        property real shift: 3

        function glitch(): void {
            glitchAnim.restart();
        }

        implicitWidth: face.implicitWidth
        implicitHeight: face.implicitHeight

        Text {
            x: -mp.shift
            y: mp.shift * 0.4
            text: mp.text
            font: face.font
            color: root.cyan
            opacity: 0.9
        }
        Text {
            x: mp.shift
            y: -mp.shift * 0.4
            text: mp.text
            font: face.font
            color: root.magenta
            opacity: 0.9
        }
        Text {
            id: face

            text: mp.text
            font.family: root.comic
            font.pixelSize: mp.size
            font.letterSpacing: 2
            color: mp.colour
        }

        SequentialAnimation {
            id: glitchAnim

            NumberAnimation { target: mp; property: "shift"; to: 14; duration: 50 }
            NumberAnimation { target: mp; property: "shift"; to: -9; duration: 50 }
            NumberAnimation { target: mp; property: "shift"; to: 18; duration: 40 }
            NumberAnimation { target: mp; property: "shift"; to: -4; duration: 60 }
            NumberAnimation { target: mp; property: "shift"; to: 3; duration: 140; easing.type: Easing.OutBack }
        }
    }

    // Yellow narration box with an ink drop shadow
    component Caption: Item {
        id: cap

        property string text
        property color bg: root.yellow
        property color fg: root.ink
        property int size: 18
        property int wrapWidth: 0 // wrap onto several lines at this width (0: one line)

        implicitWidth: (wrapWidth || capText.implicitWidth) + 22
        implicitHeight: capText.implicitHeight + 8

        Rectangle {
            antialiasing: true
            x: 4
            y: 4
            width: parent.width
            height: parent.height
            color: root.ink
        }
        Rectangle {
            antialiasing: true
            anchors.fill: parent
            color: cap.bg
            border.color: root.ink
            border.width: 2
        }
        Text {
            id: capText

            anchors.centerIn: parent
            width: cap.wrapWidth || implicitWidth
            wrapMode: cap.wrapWidth ? Text.WordWrap : Text.NoWrap
            horizontalAlignment: Text.AlignHCenter
            text: cap.text.toUpperCase()
            font.family: root.comic
            font.pixelSize: cap.size
            font.letterSpacing: 1.5
            color: cap.fg
        }
    }

    // Comic panel: ink face, light outline, hard offset shadow in an accent colour, halftone corner
    // and a caption tab on its top edge
    component Panel: Item {
        id: panel

        default property alias content: inner.data
        property string title
        property color accent: root.red
        property color dots: root.cyan
        property color titleBg: root.yellow
        property int pad: 18
        readonly property alias tab: tabCaption

        implicitWidth: inner.implicitWidth + pad * 2
        implicitHeight: inner.implicitHeight + pad * 2 + (title ? 8 : 0)

        Rectangle {
            antialiasing: true
            x: 8
            y: 8
            width: parent.width
            height: parent.height
            color: panel.accent
        }
        Rectangle {
            antialiasing: true
            anchors.fill: parent
            color: Qt.alpha(root.ink, 0.9)
            border.color: root.paper
            border.width: 2

            // The canvas clips its own dots, so the tilted panel needs no clip (which would cut it without smoothing)
            Halftone {
                antialiasing: true
                anchors.right: parent.right
                anchors.top: parent.top
                width: Math.min(parent.width, 180)
                height: Math.min(parent.height, 130)
                dot: panel.dots
                opacity: 0.4
            }
        }

        ColumnLayout {
            id: inner

            anchors.fill: parent
            anchors.margins: panel.pad
            anchors.topMargin: panel.pad + (panel.title ? 8 : 0)
            spacing: 10
        }

        Caption {
            id: tabCaption

            visible: !!panel.title
            x: -10
            y: -height / 2 - 4
            rotation: -2
            text: panel.title
            bg: panel.titleBg
            size: 17
        }
    }

    component Label: Text {
        color: root.paper
        font.family: root.mono
        font.pixelSize: 13
    }

    component Icon: Text {
        color: root.paper
        font.family: root.icons
        font.pixelSize: 22
    }

    // Slanted segment meter, turning red at the top end
    component Meter: RowLayout {
        id: meter

        property string label
        property real value
        property string detail
        property color colour: root.cyan
        readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * 12)

        spacing: 10

        Text {
            Layout.preferredWidth: 40
            text: meter.label
            font.family: root.comic
            font.pixelSize: 22
            font.letterSpacing: 1
            color: meter.colour
        }

        Row {
            spacing: 3

            Repeater {
                model: 12

                Rectangle {
                    antialiasing: true
                    required property int index

                    width: 13
                    height: 18
                    color: index < meter.lit ? (index >= 10 ? root.red : index >= 8 ? root.magenta : meter.colour) : Qt.alpha(root.paper, 0.1)
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.35, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        Text {
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: Math.round(meter.value * 100) + "%"
            font.family: root.comic
            font.pixelSize: 20
            color: root.paper
        }

        Label {
            Layout.fillWidth: true
            text: meter.detail
            color: Qt.alpha(root.paper, 0.6)
            font.pixelSize: 11
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // Over the windows while the location is being edited: what's typed is seen, and a click on a window reaches
            // clickAway (below them, it went to the window)
            WlrLayershell.layer: cityEdit.editing ? WlrLayer.Top : WlrLayer.Bottom
            WlrLayershell.namespace: "desktop-widgets"
            color: "transparent"
            // Clicks pass through to the desktop except on the media controls and the weather panel's tab (its pencil);
            // while the location is being edited, everywhere (clickAway)
            mask: Region {
                item: cityEdit.editing ? clickAway : mediaCard.visible ? mediaCard : null

                Region { item: cityEdit }
            }
            // Typing goes here only while the location is being edited. Exclusively (on demand, Hyprland never gave this
            // layer the keyboard), so a click anywhere else ends the edit first: it went to the window, and the typing
            // carried on into the field, hidden behind it
            WlrLayershell.keyboardFocus: cityEdit.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // A click outside the field while editing: cancelled, as a menu closes (that click goes no further)
            MouseArea {
                id: clickAway

                anchors.fill: parent
                enabled: cityEdit.editing
                onPressed: cityEdit.finish(false)
            }

            // Glitch the big lettering every few seconds, and on every new minute
            Timer {
                running: true
                repeat: true
                interval: 6000 + Math.random() * 9000
                onTriggered: {
                    interval = 6000 + Math.random() * 9000;
                    [hours, minutes, temp][Math.floor(Math.random() * 3)].glitch();
                }
            }

            Connections {
                target: clock

                function onDateChanged(): void {
                    if (clock.date.getSeconds() === 0) {
                        hours.glitch();
                        minutes.glitch();
                    }
                }
            }

            // The layout is drawn for a 1920x1080 screen, where the wallpaper (1920x1080 too) fills it exactly. Elsewhere
            // Caelestia crops the wallpaper to fill the screen (PreserveAspectCrop, centred), which moves the falling figure:
            // the whole layout is a 1920x1080 stage scaled and centred the same way, so it stays put around him at any size
            Item {
                id: stage

                readonly property real fit: Math.max(win.width / width, win.height / height)

                width: 1920
                height: 1080
                x: (win.width - width * fit) / 2
                y: (win.height - height * fit) / 2
                scale: fit
                transformOrigin: Item.TopLeft

                // ---- Left column: weather, calendar ----
                ColumnLayout {
                    x: stage.width * 0.30
                    // Below the band along the top that Caelestia keeps for itself on an empty workspace (dragging its
                    // panels out: its dragThreshold, 80, and its border): the weather panel's tab and pencil were in it,
                    // so the mouse never reached them. 120 screen pixels, not the stage's: scaled (1.5) or cropped (a wide
                    // screen) the stage's 120 landed inside the band, or above the screen
                    y: Math.max(stage.height * 0.08, (120 - stage.y) / stage.fit)
                    width: 290
                    spacing: 34

                    Panel {
                        id: weatherPanel

                        // (over the calendar under it while the location is edited: its suggestions show there)
                        z: cityEdit.editing ? 1 : 0
                        Layout.fillWidth: true
                        rotation: -1.5
                        title: root.city || "Forecast"
                        accent: root.magenta
                        dots: root.cyan

                        // The location: a pencil next to the tab when the mouse is over it; clicking it types a city on
                        // the tab (Enter sets it, empty for automatic by IP; Escape or clicking away cancels)
                        Item {
                            id: cityEdit

                            property bool editing: false

                            // The suggestion picked with the arrow keys (-1: none, Enter sets what's typed)
                            property int picked: -1

                            function start(): void {
                                // (a place picked before: its name to edit, not its coordinates)
                                field.text = root.places.name;
                                editing = true;
                                field.forceActiveFocus();
                                field.selectAll();
                                closeSuggestions();
                            }
                            function finish(save: bool): void {
                                if (save)
                                    root.places.apply(field.text, picked);
                                editing = false;
                                closeSuggestions();
                            }
                            function closeSuggestions(): void {
                                suggestDelay.stop();
                                root.places.closeSuggestions();
                                picked = -1;
                            }

                            Timer {
                                id: suggestDelay

                                interval: 250
                                onTriggered: root.places.suggest(field.text)
                            }

                            // New suggestions (for what's typed now): none picked, so Enter doesn't take the one that
                            // came to sit where an earlier list's pick was
                            Connections {
                                target: root.places

                                function onSuggestionsChanged(): void {
                                    cityEdit.picked = -1;
                                }
                            }

                            parent: weatherPanel.tab
                            width: (editing ? editBox.width : parent.width) + pencil.width + 10
                            height: parent.height

                            MouseArea {
                                id: cityMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: cityEdit.editing ? Qt.IBeamCursor : Qt.PointingHandCursor
                                onClicked: if (!cityEdit.editing) cityEdit.start()
                            }

                            // The same yellow box as the tab, over it, with the text being typed
                            Rectangle {
                                id: editBox

                                antialiasing: true
                                visible: cityEdit.editing
                                width: Math.max(170, field.contentWidth + 22)
                                height: parent.height
                                color: root.yellow
                                border.color: root.ink
                                border.width: 2

                                TextInput {
                                    id: field

                                    anchors.fill: parent
                                    anchors.leftMargin: 11
                                    anchors.rightMargin: 11
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: root.comic
                                    font.pixelSize: 17
                                    font.letterSpacing: 1.5
                                    font.capitalization: Font.AllUppercase
                                    color: root.ink
                                    selectionColor: root.cyan
                                    selectedTextColor: root.ink
                                    Keys.onReturnPressed: cityEdit.finish(true)
                                    Keys.onEnterPressed: cityEdit.finish(true)
                                    // Escape closes the suggestions first, then cancels
                                    Keys.onEscapePressed: root.places.suggestions.length > 0 ? cityEdit.closeSuggestions() : cityEdit.finish(false)
                                    Keys.onDownPressed: if (root.places.suggestions.length > 0 && root.places.suggestedFor === text.trim()) cityEdit.picked = Math.min(cityEdit.picked + 1, root.places.suggestions.length - 1)
                                    Keys.onUpPressed: if (root.places.suggestions.length > 0 && root.places.suggestedFor === text.trim()) cityEdit.picked = Math.max(cityEdit.picked - 1, -1)
                                    onActiveFocusChanged: if (!activeFocus && cityEdit.editing) cityEdit.finish(false)
                                    onTextEdited: {
                                        cityEdit.picked = -1;
                                        suggestDelay.restart();
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 11
                                    visible: !field.text
                                    text: "CITY (EMPTY: AUTOMATIC)"
                                    font: field.font
                                    color: Qt.alpha(root.ink, 0.45)
                                }
                            }

                            // Places matching what's typed, under the field: Up/Down and Enter, or a click, picks one (set
                            // by its coordinates, its name on the tab). Inside this window, which takes every click while
                            // editing (clickAway is under it)
                            Rectangle {
                                antialiasing: true
                                visible: cityEdit.editing && root.places.suggestions.length > 0
                                anchors.top: editBox.bottom
                                anchors.topMargin: 4
                                anchors.left: editBox.left
                                width: Math.max(editBox.width, 380)
                                height: suggestList.height + 4
                                color: root.paper
                                border.color: root.ink
                                border.width: 2

                                Column {
                                    id: suggestList

                                    x: 2
                                    y: 2
                                    width: parent.width - 4

                                    Repeater {
                                        id: suggestRepeater

                                        model: root.places.suggestions

                                        Rectangle {
                                            id: suggestion

                                            required property var modelData
                                            required property int index

                                            width: suggestList.width
                                            height: 30
                                            color: cityEdit.picked === index || suggestMouse.containsMouse ? root.yellow : "transparent"

                                            Text {
                                                id: suggestText

                                                anchors.verticalCenter: parent.verticalCenter
                                                x: 11
                                                text: root.places.placeLabel(suggestion.modelData)
                                                width: suggestion.width - 22
                                                elide: Text.ElideRight
                                                font.family: root.comic
                                                font.pixelSize: 15
                                                font.letterSpacing: 1
                                                color: root.ink
                                            }

                                            MouseArea {
                                                id: suggestMouse

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    cityEdit.picked = suggestion.index;
                                                    cityEdit.finish(true);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: pencil

                                antialiasing: true
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26
                                radius: 13
                                visible: cityMouse.containsMouse || pencilMouse.containsMouse || cityEdit.editing
                                color: pencilMouse.containsMouse ? root.red : root.ink
                                border.color: root.paper
                                border.width: 2

                                Icon {
                                    anchors.centerIn: parent
                                    text: cityEdit.editing ? "check" : "edit"
                                    color: root.paper
                                    font.pixelSize: 16
                                }

                                MouseArea {
                                    id: pencilMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: cityEdit.editing ? cityEdit.finish(true) : cityEdit.start()
                                }
                            }
                        }

                        // Until the first forecast arrives: the same layout, dimmed placeholders (a skeleton)
                        RowLayout {
                            spacing: 14
                            opacity: root.weather ? 1 : 0.3

                            Icon {
                                text: root.weather ? root.weatherIcon(root.weather.current.weather_code, root.weather.current.is_day) : "cloud"
                                color: root.cyan
                                font.pixelSize: 58
                            }

                            ColumnLayout {
                                spacing: -4

                                Misprint {
                                    id: temp

                                    text: root.weather ? Math.round(root.weather.current.temperature_2m) + "°" : "--°"
                                    size: 62
                                }
                                Text {
                                    text: root.weather ? root.weatherText(root.weather.current.weather_code).toUpperCase()
                                        : root.city.endsWith(" ?") ? "NOT FOUND" : "LOADING"
                                    font.family: root.comic
                                    font.pixelSize: 20
                                    font.letterSpacing: 1
                                    color: root.yellow
                                }
                            }
                        }

                        Label {
                            text: root.weather ? `feels ${Math.round(root.weather.current.apparent_temperature)}°  ·  ${root.weather.current.relative_humidity_2m}% humid  ·  ${Math.round(root.weather.current.wind_speed_10m)} km/h` : "feels --°  ·  --% humid  ·  -- km/h"
                            color: Qt.alpha(root.paper, root.weather ? 0.7 : 0.25)
                            font.pixelSize: 11
                        }

                        // Next three days
                        RowLayout {
                            spacing: 0
                            opacity: root.weather ? 1 : 0.3

                            Repeater {
                                model: [1, 2, 3]

                                ColumnLayout {
                                    id: day

                                    required property int modelData
                                    readonly property var d: root.weather?.daily ?? null

                                    Layout.preferredWidth: 85
                                    spacing: 0

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: day.d ? Qt.formatDate(new Date(day.d.time[day.modelData] + "T12:00"), "ddd").toUpperCase() : "---"
                                        font.family: root.comic
                                        font.pixelSize: 17
                                        font.letterSpacing: 1
                                        color: root.magenta
                                    }
                                    Icon {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: day.d ? root.weatherIcon(day.d.weather_code[day.modelData], true) : "cloud"
                                    }
                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        textFormat: Text.StyledText
                                        text: day.d ? Math.round(day.d.temperature_2m_max[day.modelData]) + "° <font color='#8f8aa8'>" + Math.round(day.d.temperature_2m_min[day.modelData]) + "°</font>" : "--° --°"
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }

                    Panel {
                        id: cal

                        // First cell of the month grid (weeks start on Monday)
                        // The day only (the clock ticks every second: the 42 cells would recompute each time)
                        readonly property date today: new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate())
                        readonly property date first: new Date(today.getFullYear(), today.getMonth(), 1)
                        readonly property int offset: (first.getDay() + 6) % 7

                        Layout.fillWidth: true
                        rotation: 1
                        title: Qt.formatDate(today, "MMMM yyyy")
                        accent: root.cyan
                        dots: root.magenta

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 2
                            columnSpacing: 2

                            Repeater {
                                model: ["M", "T", "W", "T", "F", "S", "S"]

                                Text {
                                    required property string modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.family: root.comic
                                    font.pixelSize: 17
                                    color: index >= 5 ? root.magenta : root.cyan
                                }
                            }

                            Repeater {
                                model: 42

                                Item {
                                    id: cell

                                    required property int index
                                    readonly property date d: new Date(cal.first.getFullYear(), cal.first.getMonth(), index - cal.offset + 1)
                                    readonly property bool inMonth: d.getMonth() === cal.today.getMonth()
                                    readonly property bool isToday: inMonth && d.getDate() === cal.today.getDate()

                                    // Drop the last row when the month fits in five weeks
                                    visible: index < 35 || cal.offset + new Date(cal.today.getFullYear(), cal.today.getMonth() + 1, 0).getDate() > 35
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28

                                    // Today: Miles-red dot printed off-register over a cyan one
                                    Rectangle {
                                        antialiasing: true
                                        visible: cell.isToday
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: -3
                                        anchors.verticalCenterOffset: 2
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: root.cyan
                                    }
                                    Rectangle {
                                        antialiasing: true
                                        visible: cell.isToday
                                        anchors.centerIn: parent
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: root.red
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        text: cell.d.getDate()
                                        font.pixelSize: 13
                                        font.bold: cell.isToday
                                        color: root.paper
                                        opacity: cell.inMonth ? 1 : 0.25
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Narration in the strip of sky above the falling figure's feet ----
                Caption {
                    x: stage.width * 0.463
                    y: stage.height * 0.13
                    rotation: -4
                    size: 22
                    wrapWidth: 140
                    text: root.lines[clock.date.getHours() % root.lines.length]
                }

                // ---- Right column: clock, sixth sense, media ----
                ColumnLayout {
                    x: stage.width * 0.555
                    y: stage.height * 0.05
                    width: 430
                    spacing: 0

                    // (the name caption's room, kept empty: the clock stays where it was)
                    Caption {
                        size: 20
                        opacity: 0
                    }

                    RowLayout {
                        Layout.topMargin: -6
                        spacing: 4

                        Misprint {
                            id: hours

                            text: Qt.formatTime(clock.date, "HH")
                            size: 160
                        }
                        Text {
                            text: ":"
                            font.family: root.comic
                            font.pixelSize: 140
                            color: root.red
                            // A hard blink, not a fade: a fade redrew the widgets ~20 times a second, all the time
                            opacity: clock.date.getSeconds() % 2 ? 0.3 : 1
                        }
                        Misprint {
                            id: minutes

                            text: Qt.formatTime(clock.date, "mm")
                            size: 160
                        }
                    }

                    Caption {
                        Layout.topMargin: -14
                        Layout.leftMargin: 40
                        rotation: 2
                        size: 24
                        text: Qt.formatDate(clock.date, "dddd, d MMMM")
                    }

                    Panel {
                        id: sense

                        Layout.fillWidth: true
                        Layout.topMargin: 40
                        rotation: 1
                        title: root.tingling ? "Sixth sense tingling!" : "Sixth sense"
                        titleBg: root.tingling ? root.red : root.yellow
                        accent: root.tingling ? root.red : root.sky
                        dots: root.magenta

                        // Shake while tingling; not behind a fullscreen window (a game runs the GPU that hot, and the
                        // widgets were redrawn under it the whole time)
                        SequentialAnimation on rotation {
                            running: root.tingling && !(Hyprland.focusedWorkspace?.hasFullscreen ?? false)
                            loops: Animation.Infinite
                            onStopped: sense.rotation = 1
                            NumberAnimation { to: -1.5; duration: 70 }
                            NumberAnimation { to: 2.5; duration: 70 }
                            NumberAnimation { to: 1; duration: 70 }
                            PauseAnimation { duration: 900 }
                        }

                        Meter {
                            label: "CPU"
                            value: root.cpu
                            detail: root.cpuTemp > 0 ? root.cpuTemp + "°C" : ""
                        }
                        Meter {
                            label: "RAM"
                            value: root.ram
                            detail: root.ramUsedGb.toFixed(1) + " GB"
                        }
                        Meter {
                            visible: root.gpu >= 0
                            label: "GPU"
                            value: root.gpu
                            detail: root.gpuTemp + "°C"
                        }
                        Meter {
                            label: "SSD"
                            value: root.disk
                            detail: root.diskText
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Icon { text: "south"; font.pixelSize: 16; color: root.cyan }
                            Label { text: root.human(root.netDown); font.pixelSize: 12; Layout.preferredWidth: 80 }
                            Icon { text: "north"; font.pixelSize: 16; color: root.magenta }
                            Label { text: root.human(root.netUp); font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Label { text: "UP " + root.uptime; color: Qt.alpha(root.paper, 0.6); font.pixelSize: 11 }
                        }
                    }

                    Panel {
                        id: mediaCard

                        Layout.fillWidth: true
                        Layout.topMargin: 36
                        rotation: -1
                        title: "Now playing"
                        accent: root.magenta
                        dots: root.cyan

                        // Until a player (Spotify, started in the tray a moment after this) is there: dimmed, a skeleton
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            opacity: root.player ? 1 : 0.3

                            // Cover art, misprinted
                            Item {
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 88
                                rotation: -3

                                Rectangle { antialiasing: true; x: -4; y: 3; width: 88; height: 88; color: root.cyan }
                                Rectangle { antialiasing: true; x: 4; y: -3; width: 88; height: 88; color: root.magenta }
                                Rectangle {
                                    antialiasing: true
                                    anchors.fill: parent
                                    color: root.ink
                                    border.color: root.paper
                                    border.width: 2

                                    Icon {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        color: root.paper
                                        font.pixelSize: 36
                                    }
                                    Image {
                                        antialiasing: true
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: root.player?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize: Qt.size(176, 176)
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: (root.player?.trackTitle || "Nothing playing").toUpperCase()
                                    font.family: root.comic
                                    font.pixelSize: 24
                                    font.letterSpacing: 1
                                    color: root.paper
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: root.player?.trackArtist || root.player?.identity || ""
                                    color: root.yellow
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                // Progress: web line
                                Item {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    Layout.preferredHeight: 6

                                    Rectangle {
                                        antialiasing: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 2
                                        color: Qt.alpha(root.paper, 0.2)
                                    }
                                    Rectangle {
                                        antialiasing: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * (root.player && root.player.length > 0 ? Math.min(1, root.player.position / root.player.length) : 0)
                                        height: 4
                                        color: root.red
                                    }
                                }

                                RowLayout {
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { icon: "skip_previous", act: () => root.player.previous(), on: root.player?.canGoPrevious ?? false },
                                            { icon: root.player?.isPlaying ? "pause" : "play_arrow", act: () => root.player.togglePlaying(), on: root.player?.canTogglePlaying ?? false },
                                            { icon: "skip_next", act: () => root.player.next(), on: root.player?.canGoNext ?? false }
                                        ]

                                        Rectangle {
                                            id: btn

                                            antialiasing: true
                                            required property var modelData

                                            implicitWidth: 34
                                            implicitHeight: 34
                                            radius: 17
                                            opacity: modelData.on ? 1 : 0.4
                                            color: btnMouse.containsMouse ? root.red : "transparent"

                                            Icon {
                                                anchors.centerIn: parent
                                                text: btn.modelData.icon
                                                color: btnMouse.containsMouse ? root.paper : root.cyan
                                                font.pixelSize: 26
                                            }

                                            MouseArea {
                                                id: btnMouse

                                                anchors.fill: parent
                                                enabled: btn.modelData.on
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: btn.modelData.act()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // THWIP! on every new track
                        Text {
                            id: thwip

                            parent: mediaCard
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -18
                            anchors.topMargin: -26
                            text: "THWIP!"
                            font.family: root.comic
                            font.pixelSize: 38
                            font.letterSpacing: 2
                            color: root.red
                            style: Text.Outline
                            styleColor: root.paper
                            rotation: 12
                            scale: 0
                            opacity: 0

                            SequentialAnimation {
                                id: thwipAnim

                                ParallelAnimation {
                                    NumberAnimation { target: thwip; property: "scale"; from: 0.3; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                    NumberAnimation { target: thwip; property: "opacity"; to: 1; duration: 80 }
                                }
                                PauseAnimation { duration: 1400 }
                                NumberAnimation { target: thwip; property: "opacity"; to: 0; duration: 300 }
                            }

                            Connections {
                                target: root.player

                                function onTrackTitleChanged(): void {
                                    thwipAnim.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
