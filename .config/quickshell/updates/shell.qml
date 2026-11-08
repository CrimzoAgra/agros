// Updates: a window in Caelestia's style listing what's waiting (system and AUR apps, Flatpaks, AppImages), with
// "Update all", which runs ~/.local/bin/update-apps and shows its progress.
//   qs -c updates -n                  open it (Super menu: "Updates")
//   UPDATES_START=1 qs -c updates -n  open it and start updating (the "Update now" notification)
// Closing the window quits it (an update already running carries on, its log in $XDG_RUNTIME_DIR/update-apps.log). Separate from Caelestia, so Caelestia updates don't touch it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string script: `${home}/.local/bin/update-apps`

    // Caelestia's colours: ../common/Scheme.qml (not an import: Quickshell blocks those from outside this folder)
    Loader {
        id: scheme
        source: `file://${Quickshell.shellPath("../common/Scheme.qml")}`
    }
    function c(name: string): color {
        return scheme.item?.c(name) ?? "transparent";
    }

    // checking -> ready -> updating -> done (then checking again)
    property string phase: "checking"
    property var items: [] // { kind, name, old, new }
    property var log: []
    property string step: "" // the part being updated now ("System and AUR apps"...)
    property bool failed: false
    property bool startWhenReady: Quickshell.env("UPDATES_START") === "1"

    readonly property var pending: items.filter(i => i.kind !== "offline")
    readonly property bool offline: items.some(i => i.kind === "offline")
    readonly property var groups: [
        { title: "System and apps", kinds: ["system", "aur", "capri"] },
        { title: "Flatpaks", kinds: ["flatpak"] },
        { title: "AppImages", kinds: ["appimage"] }
    ]

    function check(): void {
        phase = "checking";
        listProc.running = true;
    }

    function updateAll(): void {
        log = [];
        step = "";
        failed = false;
        phase = "updating";
        updateProc.running = true;
    }

    // The app that goes with a package, for its name and icon (visual-studio-code-bin -> Visual Studio Code...)
    function entryFor(item: var): var {
        // AppImages are listed by GitHub repo: SomeOwner/AppDesktop -> app
        const names = [item.name, item.name.replace(/-(bin|git|appimage)$/, ""), item.name.split("/").pop().toLowerCase().replace(/desktop$/, "")];
        for (const n of names) {
            const e = DesktopEntries.byId(n) ?? DesktopEntries.heuristicLookup(n);
            if (e)
                return e;
        }
        return null;
    }

    Process {
        id: listProc

        running: true
        // Ends with a line of its own: with nothing to update the list is empty, and empty output never reported back
        // (the count from before the update stayed)
        command: ["sh", "-c", `"${root.script}" --list; echo end`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.items = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const [kind, name, old, now] = l.split("\t");
                    return { kind, name, old: old ?? "", new: now ?? "" };
                });
                root.phase = root.phase === "done" ? "done" : "ready";
                if (root.startWhenReady) {
                    root.startWhenReady = false;
                    if (root.pending.length)
                        root.updateAll();
                }
            }
        }
    }

    Process {
        id: updateProc

        // Its output and errors together, line by line. In a session of its own writing to a file the window follows:
        // closing the window then stops only the following, never the update (pacman cut off mid-upgrade)
        // One at a time: the update holds a lock for as long as it runs (the window may have been closed and opened
        // again meanwhile); a second "Update all" follows that one's log instead, and ends as it did (its exit code is kept
        // next to the log). Each follower ends with its shell (a window closed meanwhile)
        // (the lock not passed on to the update: a background job of it, git gc after paru, held it after the update ended)
        command: ["sh", "-c", 'exec 9>"$1.lock"; if ! flock -n 9; then echo "== An update started earlier is still running"; tail -n +1 -f --pid=$$ "$1" 9>&- & t=$!; flock 9; sleep 1; kill $t; exit "$(cat "$1.status" 2>/dev/null || echo 1)"; fi; : >"$1"; rm -f "$1.status"; (setsid "$0" 9>&- >"$1" 2>&1 </dev/null; echo $? >"$1.status") & p=$!; exec 9>&-; tail -n +1 -f --pid=$p "$1" & t=$!; wait $p; wait $t; exit "$(cat "$1.status" 2>/dev/null || echo 1)"',
            root.script, `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/update-apps.log`]
        stdout: SplitParser {
            onRead: line => {
                const clean = line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\r").pop();
                if (clean.startsWith("== "))
                    root.step = clean.slice(3);
                root.log = [...root.log.slice(-400), clean];
            }
        }
        onExited: (code, status) => {
            // update-apps' exit code says whether a step failed (a package name like libgpg-error isn't an error)
            if (code !== 0)
                root.failed = true;
            root.phase = "done";
            root.items = []; // the list from before the update: not offered again while what's left is looked up
            listProc.running = true; // what's left, if anything
        }
    }

    component Button: Rectangle {
        id: btn

        property string label
        property string icon
        property bool primary
        signal clicked

        implicitWidth: btnRow.implicitWidth + 36
        implicitHeight: 44
        radius: 22
        opacity: enabled ? 1 : 0.4
        color: primary ? (mouse.containsMouse ? root.c("primaryFixed") : root.c("primary"))
             : (mouse.containsMouse ? root.c("surfaceContainerHighest") : root.c("surfaceContainerHigh"))

        RowLayout {
            id: btnRow

            anchors.centerIn: parent
            spacing: 8

            Text {
                text: btn.icon
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
                color: btn.primary ? root.c("onPrimary") : root.c("onSurface")
            }
            Text {
                text: btn.label
                font.family: "Rubik"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: btn.primary ? root.c("onPrimary") : root.c("onSurface")
            }
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    FloatingWindow {
        id: win

        title: "Updates"
        implicitWidth: 600
        implicitHeight: 680
        color: root.c("surface")
        onVisibleChanged: if (!visible) Qt.quit()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            // Header
            RowLayout {
                spacing: 16

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 18
                    color: root.c("primaryContainer")

                    Text {
                        id: headerIcon

                        anchors.centerIn: parent
                        text: root.phase === "updating" ? "downloading" : root.phase === "checking" ? "sync" : root.pending.length ? "system_update" : "verified"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 30
                        color: root.c("onPrimaryContainer")

                        RotationAnimation on rotation {
                            running: root.phase === "checking"
                            from: 360
                            to: 0
                            duration: 1200
                            loops: Animation.Infinite
                            onStopped: headerIcon.rotation = 0
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.phase === "checking" ? "Checking for updates…"
                            : root.phase === "updating" ? "Updating…"
                            : root.phase === "done" && root.failed ? "Finished, with problems"
                            : listProc.running ? "Checking what's left…"
                            : root.pending.length ? `${root.pending.length} update${root.pending.length > 1 ? "s" : ""} available`
                            : "Everything is up to date"
                        font.family: "Rubik"
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: root.c("onSurface")
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.phase === "updating" ? (root.step || "Starting") + (root.step === "Flatpaks" ? " (system ones may ask for your password)" : "")
                            : root.phase === "done" && root.failed ? "Something didn't update; the details are below"
                            : root.phase === "done" ? "All done"
                            : "System, AUR apps, Flatpaks and AppImages"
                        font.family: "Rubik"
                        font.pixelSize: 13
                        color: root.c("onSurfaceVariant")
                        elide: Text.ElideRight
                    }
                }
            }

            // The list, or the progress while updating
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: root.c("surfaceContainer")

                Flickable {
                    id: listView

                    visible: root.phase !== "updating" && !(root.phase === "done" && root.log.length)
                    anchors.fill: parent
                    anchors.margins: 8
                    contentHeight: listCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: listCol

                        width: listView.width
                        spacing: 2

                        Text {
                            visible: root.phase !== "checking" && !listProc.running && (!root.items.length || root.offline)
                            Layout.fillWidth: true
                            Layout.topMargin: 40
                            horizontalAlignment: Text.AlignHCenter
                            text: root.offline ? "Couldn't check: no connection to the package servers" : "Nothing to update"
                            font.family: "Rubik"
                            font.pixelSize: 15
                            color: root.c("onSurfaceVariant")
                        }

                        Repeater {
                            model: root.groups

                            ColumnLayout {
                                id: group

                                required property var modelData
                                readonly property var rows: root.items.filter(i => modelData.kinds.includes(i.kind))

                                visible: rows.length > 0
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.leftMargin: 12
                                    Layout.topMargin: 10
                                    Layout.bottomMargin: 4
                                    text: group.modelData.title
                                    font.family: "Rubik"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: root.c("primary")
                                }

                                Repeater {
                                    model: group.rows

                                    Rectangle {
                                        id: row

                                        required property var modelData
                                        // Looked up again once the app list has loaded (it loads in the background)
                                        readonly property var entry: (DesktopEntries.applications.values.length, root.entryFor(modelData))
                                        readonly property string icon: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""

                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: 14
                                        color: hover.hovered ? root.c("surfaceContainerHigh") : "transparent"

                                        HoverHandler {
                                            id: hover
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 12

                                            Item {
                                                implicitWidth: 28
                                                implicitHeight: 28

                                                IconImage {
                                                    visible: !!row.icon
                                                    anchors.fill: parent
                                                    source: row.icon
                                                }
                                                Text {
                                                    visible: !row.icon
                                                    anchors.centerIn: parent
                                                    text: row.modelData.kind === "flatpak" ? "deployed_code" : row.modelData.kind === "appimage" ? "apps" : "package_2"
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: 22
                                                    color: root.c("onSurfaceVariant")
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: row.entry?.name ?? row.modelData.name
                                                    font.family: "Rubik"
                                                    font.pixelSize: 14
                                                    color: root.c("onSurface")
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    visible: !!row.entry
                                                    Layout.fillWidth: true
                                                    text: row.modelData.name
                                                    font.family: "Rubik"
                                                    font.pixelSize: 11
                                                    color: root.c("onSurfaceVariant")
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Text {
                                                Layout.maximumWidth: 260
                                                text: (row.modelData.old ? row.modelData.old + "  →  " : "") + row.modelData.new
                                                font.family: "CaskaydiaCove NF"
                                                font.pixelSize: 11
                                                color: root.c("onSurfaceVariant")
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Progress: the update's own output, following the end
                ListView {
                    id: logView

                    visible: !listView.visible
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    model: root.log
                    onCountChanged: positionViewAtEnd()

                    delegate: Text {
                        required property string modelData

                        width: logView.width
                        text: modelData
                        wrapMode: Text.WrapAnywhere
                        font.family: "CaskaydiaCove NF"
                        font.pixelSize: 11
                        color: modelData.startsWith("== ") ? root.c("primary") : /(^|\s)error:/i.test(modelData) ? root.c("error") : root.c("onSurfaceVariant")
                    }
                }
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    label: root.phase === "done" && root.log.length ? "Back to the list" : "Check again"
                    icon: root.phase === "done" && root.log.length ? "list" : "refresh"
                    enabled: root.phase === "ready" || root.phase === "done"
                    onClicked: {
                        if (root.phase === "done" && root.log.length)
                            root.log = [];
                        else
                            root.check();
                    }
                }

                Button {
                    primary: true
                    label: "Update all"
                    visible: root.pending.length > 0 || root.phase === "updating"
                    icon: "download"
                    enabled: root.phase !== "checking" && root.phase !== "updating" && root.pending.length > 0
                    onClicked: root.updateAll()
                }
            }
        }
    }
}
