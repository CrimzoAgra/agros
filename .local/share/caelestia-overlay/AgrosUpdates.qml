pragma ComponentBehavior: Bound

// caelestia-overlay: AgrOS's Updates, a page of Nexus (the Updates app it replaced was a window of its own). It lists
// what's waiting (system
// and AUR apps, firmware, Flatpaks, AppImages, Proton builds, developer tools), each with its app's icon and name, and
// "Update all" runs ~/.local/bin/update-apps, its output shown as it goes. This page lives inside Caelestia, which an
// update can restart: so the update runs in a systemd unit of its own (agros-update-apps), writing to
// $XDG_RUNTIME_DIR/update-apps.log, which the page only follows. Closed and opened again, or Caelestia restarted, the
// page finds the update still running and follows it again. One at a time (the log's lock). Opened from update-apps'
// notifications (nexus updates: settings_open_at in patch.py), what the check found shown at once, and "Update now"
// started. An account that isn't an admin's sees the list, told so, and no "Update all"

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string script: `${Quickshell.env("HOME")}/.local/bin/update-apps`
    readonly property string logFile: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/update-apps.log`

    // checking -> ready -> updating -> done (then checking again)
    property string phase: "checking"
    property var items: [] // { kind, name, old, new }
    property var log: []
    property string step: "" // the part being updated now ("System and AUR apps"...)
    property bool failed: false
    property bool listFailed: false // the list couldn't be made (update-apps missing or broken): not "nothing to update"
    // An admin's (wheel) alone can install them (update-apps uses sudo): another account sees the list, told so, and
    // no "Update all", which only failed (the boot's update installs them all the same)
    property bool admin: true
    // Opened from a check's notification (nexus updates: AgrosSettings): the list that check found, shown at once (a
    // file; checked anew when it's older than 15 minutes; used once: after an update, checked anew), and "Update now"'s
    // start once it's read
    property string listFile
    property bool startWhenReady

    readonly property var pending: items.filter(i => i.kind !== "offline")
    readonly property bool offline: items.some(i => i.kind === "offline")
    readonly property var groups: [
        { title: "System and apps", kinds: ["system", "aur"] },
        { title: "Firmware", kinds: ["firmware"] },
        { title: "Flatpaks", kinds: ["flatpak"] },
        { title: "AppImages", kinds: ["appimage"] },
        { title: "Proton and developer tools", kinds: ["proton", "dev"] }
    ]
    readonly property bool showLog: phase === "updating" || (phase === "done" && log.length > 0)

    function check(): void {
        phase = "checking";
        listProc.running = true;
    }

    // start: run an update (unless one is running: followed instead); else follow one if it's running, or check
    function follow(start: bool): void {
        updateProc.start = start;
        updateProc.running = true;
    }

    function updateAll(): void {
        log = [];
        step = "";
        failed = false;
        phase = "updating";
        follow(true);
    }

    // A line of the update's log shown red: an error, but not pacman's "failed retrieving file ... from <mirror>" (that
    // mirror didn't have it: the next one is tried, and the update goes on; "failed to retrieve some files", when none
    // had it, stays red, as does "Finished, with problems")
    function isError(line: string): bool {
        return /(^|\s)error:/i.test(line) && !/error: failed retrieving file .* from /i.test(line);
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

    title: "Updates"

    // (an update already running, from before the page was opened: followed; none, the list)
    Component.onCompleted: {
        listFile = AgrosSettings.updatesList;
        startWhenReady = AgrosSettings.updatesStart;
        AgrosSettings.updatesList = "";
        AgrosSettings.updatesStart = false;
        follow(false);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: listProc

            // Ends with a line of its own, with the list's exit status: with nothing to update the list is empty, and
            // empty output never reported back; a list that failed said as such. One that hangs (a network that
            // connects but never answers: checkupdates, paru and flatpak have no time limit of their own) fails after
            // 10 minutes, with everything it started (timeout signals its whole process group). Ended with Caelestia
            // too, however it goes (setpriv's pdeathsig): else it ran on for those 10 minutes
            // A check's list (listFile) instead, when it's from the last 15 minutes; removed either way
            command: ["sh", "-c", 'if [ -n "$1" ] && [ "$(($(date +%s) - $(stat -c %Y "$1" 2>/dev/null || echo 0)))" -lt 900 ]; then cat "$1"; echo "end 0"; else setpriv --pdeathsig TERM timeout 10m "$0" --list; echo "end $?"; fi; [ -z "$1" ] || rm -f "$1"', root.script, root.listFile]
            stdout: StdioCollector {
                onStreamFinished: {
                    root.listFile = "";
                    root.listFailed = !/^end 0$/m.test(text);
                    root.items = root.listFailed ? [] : text.split("\n").filter(l => l.includes("\t")).map(l => {
                        const [kind, name, old, now] = l.split("\t");
                        return { kind, name, old: old ?? "", new: now ?? "" };
                    });
                    if (root.phase === "checking")
                        root.phase = "ready";
                    if (root.startWhenReady) {
                        root.startWhenReady = false;
                        if (root.pending.length && root.admin)
                            root.updateAll();
                    }
                }
            }
        }

        // (admin: this account in wheel)
        Process {
            running: true
            command: ["id", "-nG"]
            stdout: StdioCollector {
                onStreamFinished: root.admin = ` ${text.trim()} `.includes(" wheel ")
            }
        }

        Process {
            id: updateProc

            property bool start

            // The update in a systemd unit of its own (agros-update-apps), not a child of Caelestia: an update that
            // restarts Caelestia (a rebuild for a new Qt) doesn't cut itself off, nor does closing Nexus. Its output and
            // errors go to the log, which this follows from the start; its exit code is kept next to it (.status).
            // Running: that unit active, or the lock held (the unit waits a moment for one, then leaves that one be).
            // A second "Update all", or the page opened again,
            // follows the running one's log instead, and ends as it did. Exit 100: none running (to follow).
            // An update logged out of: its pacman carries on in a system unit (agros-pacman, update-apps' paru-sudo),
            // the rest of it and its log gone; waited for, said, then the list looked up again (exit 100).
            // The follower ends with Caelestia (pdeathsig), its tail with it (--pid)
            command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", `running() { systemctl --user is-active -q agros-update-apps || ! flock -n "$1.lock" true; }
                if running "$1"; then echo "== An update started earlier is still running"
                elif systemctl is-active -q agros-pacman; then
                    echo "== An install started earlier (before a logout) is still finishing"
                    while systemctl is-active -q agros-pacman; do sleep 1; done
                    exit 100
                elif [ "$2" = start ]; then
                    : >"$1"; rm -f "$1.status"
                    systemd-run --user --unit=agros-update-apps --collect --quiet sh -c "$3" "$0" "$1" ||
                        { echo "error: systemd-run failed, the update was not started"; exit 1; }
                else exit 100; fi
                tail -n +1 -F --pid=$$ "$1" 2>/dev/null & t=$!
                while running "$1"; do sleep 1; done
                sleep 1; kill $t 2>/dev/null
                exit "$(cat "$1.status" 2>/dev/null || echo 1)"`,
                root.script, root.logFile, updateProc.start ? "start" : "",
                // (the unit's: the lock not passed on to the update: a background job of it, git gc after paru, held it
                // after the update ended)
                'exec 9>"$1.lock"; flock -w 5 9 || exit 0; "$0" 9>&- >>"$1" 2>&1 </dev/null; echo $? >"$1.status"']
            stdout: SplitParser {
                onRead: line => {
                    const clean = line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\r").pop();
                    if (clean.startsWith("== "))
                        root.step = clean.slice(3);
                    root.phase = "updating";
                    root.log = [...root.log.slice(-400), clean];
                }
            }
            onExited: code => {
                if (code === 100) {
                    root.check();
                    return;
                }
                // update-apps' exit code says whether a step failed (a package name like libgpg-error isn't an error)
                root.failed = code !== 0;
                root.startWhenReady = false; // (one was running already: not another after it)
                root.phase = "done";
                root.items = []; // the list from before the update: not offered again while what's left is looked up
                listProc.running = true; // what's left, if anything
            }
        }

        // Header: how it stands, and the buttons
        ConnectedRect {
            id: header

            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: headerCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: headerCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large

                    StyledRect {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            id: headerIcon

                            anchors.centerIn: parent
                            text: root.phase === "updating" ? "downloading" : root.phase === "checking" ? "sync" : root.listFailed ? "error" : root.pending.length ? "system_update" : root.offline ? "error" : "verified"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.large

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
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.phase === "checking" ? "Checking for updates…"
                                : root.phase === "updating" ? "Updating…"
                                : root.phase === "done" && root.failed ? "Finished, with problems"
                                : listProc.running ? "Checking what's left…"
                                : root.listFailed ? "Couldn't check for updates"
                                : root.pending.length ? `${root.pending.length} update${root.pending.length > 1 ? "s" : ""} available`
                                : root.offline ? "Couldn't check for updates" // (no connection: not "up to date")
                                : "Everything is up to date"
                            font: Tokens.font.title.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.phase === "updating" ? (root.step || "Starting") + (root.step === "Flatpaks" ? " (system ones may ask for your password)" : "")
                                : root.phase === "done" && root.failed ? "Something didn't update; the details are below"
                                : root.phase === "done" ? "All done"
                                : !root.admin && root.pending.length ? "An administrator has to install these updates"
                                : "System, AUR apps, firmware, Flatpaks, AppImages, Proton and developer tools"
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            wrapMode: Text.Wrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    IconTextButton {
                        type: ButtonBase.Tonal
                        text: root.phase === "done" && root.log.length ? "Back to the list" : "Check again"
                        icon: root.phase === "done" && root.log.length ? "list" : "refresh"
                        disabled: root.phase !== "ready" && root.phase !== "done"
                        onClicked: {
                            if (root.phase === "done" && root.log.length)
                                root.log = [];
                            else
                                root.check();
                        }
                    }

                    // After an update: restart for what only takes effect then (a kernel, a driver). Asks for a second
                    // click, as it appears where "Update all" was, under the pointer, and closes everything
                    IconTextButton {
                        type: root.pending.length === 0 ? ButtonBase.Filled : ButtonBase.Tonal
                        text: confirm.running ? "Click again to restart" : "Restart"
                        icon: "restart_alt"
                        visible: root.phase === "done"
                        onVisibleChanged: confirm.stop()
                        onClicked: {
                            if (confirm.running)
                                Quickshell.execDetached(["systemctl", "reboot"]);
                            else
                                confirm.restart();
                        }

                        Timer {
                            id: confirm

                            interval: 4000
                        }
                    }

                    IconTextButton {
                        type: ButtonBase.Filled
                        text: "Update all"
                        icon: "download"
                        visible: root.admin && root.pending.length > 0 || root.phase === "updating"
                        disabled: root.phase === "checking" || root.phase === "updating" || root.pending.length === 0
                        // It appears where "Check again" was (nothing waiting before), under the pointer: a click there
                        // for a moment after is the second of a double-click on that, or one more on it, not an install
                        onVisibleChanged: if (visible) justShown.restart()
                        onClicked: if (!justShown.running) root.updateAll()

                        Timer {
                            id: justShown

                            interval: 1000
                        }
                    }
                }
            }
        }

        // Nothing to list: why
        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            visible: !root.showLog && root.phase !== "checking" && !listProc.running && (!root.items.length || root.offline || root.listFailed)
            first: true
            last: true
            implicitHeight: emptyText.implicitHeight + Tokens.padding.extraLarge * 2

            StyledText {
                id: emptyText

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.listFailed ? "Couldn't check: update-apps --list failed (run it in a terminal to see why)"
                    : root.offline ? "Couldn't check: no connection to the package servers" : "Nothing to update"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        // The list, by group
        Repeater {
            model: root.showLog ? [] : root.groups

            ColumnLayout {
                id: group

                required property var modelData
                readonly property var rows: root.items.filter(i => modelData.kinds.includes(i.kind))

                Layout.fillWidth: true
                visible: rows.length > 0
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: group.modelData.title
                }

                Repeater {
                    model: group.rows

                    ConnectedRect {
                        id: row

                        required property var modelData
                        required property int index
                        // Looked up again once the app list has loaded (it loads in the background)
                        readonly property var entry: (DesktopEntries.applications.values.length, root.entryFor(modelData))
                        readonly property string icon: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""

                        Layout.fillWidth: true
                        first: index === 0
                        last: index === group.rows.length - 1
                        implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2
                        color: hover.hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

                        HoverHandler {
                            id: hover
                        }

                        RowLayout {
                            id: rowLayout

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.largeIncreased
                            anchors.rightMargin: Tokens.padding.largeIncreased
                            spacing: Tokens.spacing.medium

                            Item {
                                implicitWidth: 28
                                implicitHeight: 28

                                IconImage {
                                    visible: !!row.icon
                                    anchors.fill: parent
                                    source: row.icon
                                }

                                MaterialIcon {
                                    visible: !row.icon
                                    anchors.centerIn: parent
                                    text: row.modelData.kind === "flatpak" ? "deployed_code" : row.modelData.kind === "appimage" ? "apps" : row.modelData.kind === "firmware" ? "memory" : row.modelData.kind === "proton" ? "sports_esports" : row.modelData.kind === "dev" ? "terminal" : "package_2"
                                    color: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.medium
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.entry?.name ?? row.modelData.name
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !!row.entry
                                    text: row.modelData.name
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }

                            StyledText {
                                // (all of it while hovered, the name cut instead: a long version, 2.44+r78+g…, had no
                                // way to be seen; cut at the end: both versions stay, a long "asks for more access" goes)
                                Layout.maximumWidth: hover.hovered ? row.width - 120 : 260
                                text: (row.modelData.old ? row.modelData.old + "  →  " : "") + row.modelData.new
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.mono.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // Progress: the update's own output, following the end (as tall as the page leaves room for)
        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            visible: root.showLog
            first: true
            last: true
            implicitHeight: Math.max(300, root.flickable.height - header.height - Tokens.spacing.large - root.flickable.topMargin - root.flickable.bottomMargin)

            StyledListView {
                id: logView

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                clip: true
                model: root.showLog ? root.log : []
                onCountChanged: positionViewAtEnd()

                delegate: StyledText {
                    required property string modelData

                    width: logView.width
                    text: modelData
                    wrapMode: Text.WrapAnywhere
                    font: Tokens.font.mono.small
                    color: modelData.startsWith("== ") ? Colours.palette.m3primary : root.isError(modelData) ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
