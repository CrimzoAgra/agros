// Caelestia-style login screen for greetd, modelled on Caelestia's lock screen.
// Installed to /etc/greetd/caelestia-greeter by ~/.local/share/caelestia-greeter/install.sh (run with sudo).
// The wallpaper and Caelestia colours are copied into theme/ by make-theme.sh at every login.
// Preview on the desktop (no logging in):
//   ~/.local/share/caelestia-greeter/make-theme.sh ~/.local/share/caelestia-greeter/theme && qs -p ~/.local/share/caelestia-greeter
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import M3Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

ShellRoot {
    id: root

    // Colours, user and wallpaper: theme/theme.json next to this file (refreshed at every login by make-theme.sh)
    property var theme: ({})
    readonly property var c: theme.colours ?? {}
    // (theme.json is rewritten at every login; install.sh also puts the user in the environment, in case it's broken)
    readonly property string user: theme.user || Quickshell.env("CAELESTIA_GREETER_USER") || ""
    readonly property string wallpaper: theme.wallpaper ?? `${Quickshell.shellDir}/theme/wallpaper`

    function col(name: string, fallback: string): color {
        return "#" + (c[name] ?? fallback);
    }

    readonly property color primary: col("primary", "c2c1ff")
    readonly property color secondary: col("secondary", "c6c4e0")
    readonly property color surface: col("surface", "131317")
    readonly property color surfaceContainer: col("surfaceContainer", "201f23")
    readonly property color surfaceContainerHigh: col("surfaceContainerHigh", "2a292e")
    readonly property color surfaceContainerHighest: col("surfaceContainerHighest", "353438")
    readonly property color fg: col("onSurface", "e5e1e7")
    readonly property color fgVariant: col("onSurfaceVariant", "c8c5d1")
    readonly property color error: col("error", "ffb4ab")

    readonly property string font: "Rubik"
    readonly property string iconFont: "Material Symbols Rounded"

    // Sessions from /usr/share/wayland-sessions: [{ name, exec, desktop }]
    property var sessions: [{ name: "Hyprland (uwsm-managed)", exec: "uwsm start -e -D Hyprland hyprland.desktop", desktop: "Hyprland" }]
    property int sessionIdx: 0
    readonly property var session: sessions[sessionIdx] ?? sessions[0]

    property string message
    property bool busy

    // If the last session ended within 20 s of being started here, it probably failed:
    // start the next one plainly (without sending its messages to the log)
    readonly property string launchFile: `${Quickshell.env("XDG_STATE_HOME") || "/tmp"}/caelestia-greeter-last-launch`
    readonly property bool safeMode: {
        const t = parseInt(lastLaunch.text()) || 0;
        // (a launch time ahead of the clock: the clock was set back since, e.g. a boot after Windows, not a failed session)
        return Date.now() - t >= 0 && Date.now() - t < 20000;
    }
    property string password
    property bool passwordSent // this attempt's password went to its password prompt
    property string pamMessage // what PAM last said during this attempt (an account locked for N minutes...)
    property bool answering // another prompt (a code...) waits for what's typed next

    function login(): void {
        if (busy || !password)
            return;
        if (!Greetd.available) {
            message = "Preview only: not running under greetd";
            return;
        }
        if (answering) {
            answering = false;
            busy = true;
            Greetd.respond(password);
            password = "";
            return;
        }
        // No user (theme.json broken and none in the environment): greetd can't start, and would leave it spinning
        if (!user) {
            message = "No user set: run the login screen's install.sh again";
            return;
        }
        busy = true;
        passwordSent = false;
        pamMessage = "";
        message = "";
        Greetd.createSession(user);
    }

    FileView {
        id: lastLaunch

        path: root.launchFile
        blockLoading: true
        blockWrites: true // written before the login screen closes: its start script reads it to tell a login from a crash
        printErrors: false
    }

    FileView {
        path: `${Quickshell.shellDir}/theme/theme.json`
        onLoaded: {
            try {
                root.theme = JSON.parse(text());
            } catch (e) {}
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do n=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); e=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); d=$(grep -m1 '^DesktopNames=' \"$f\" | cut -d= -f2- | cut -d';' -f1); printf '%s\\t%s\\t%s\\n' \"$n\" \"$e\" \"$d\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.trim().split("\n").filter(l => l.includes("\t")).map(l => {
                    const [name, exec, desktop] = l.split("\t");
                    return { name, exec, desktop: desktop || name.split(" ")[0] };
                }).filter(x => x.exec.trim()); // one with no command would launch nothing, back to this screen
                if (!list.length)
                    return;
                // uwsm-managed Hyprland first: it's what this setup needs (plain Hyprland exits straight away)
                const rank = x => x.exec.startsWith("uwsm") ? 0 : x.name.startsWith("Hyprland") ? 1 : 2;
                list.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
                root.sessions = list;
                root.sessionIdx = 0;
            }
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            // The password goes to the password prompt only (the first hidden one); any other prompt (a one-time
            // code...) is shown, and what's typed next answers it
            if (responseRequired && !echoResponse && !root.passwordSent) {
                root.passwordSent = true;
                Greetd.respond(root.password);
            } else if (responseRequired) {
                root.busy = false;
                root.answering = true;
                root.password = "";
                root.message = message;
            } else {
                root.message = message; // information too (an account locked for N minutes...)
                root.pamMessage = message;
            }
        }

        function onReadyToLaunch(): void {
            const desktop = root.session.desktop ?? "Hyprland";
            // Same as other greeters: the session's command split into words (desktop-file Exec has no quoting here)
            // systemd-cat: the session's messages go to the system log instead of showing on screen
            const cmd = root.session.exec.split(" ").filter(w => w);
            // Read before the launch time is saved: safeMode follows that file, and would compare the new time with itself
            const safe = root.safeMode;
            lastLaunch.setText(String(Date.now()));
            Greetd.launch(safe ? cmd : ["systemd-cat", "-t", "desktop-session", ...cmd], ["XDG_SESSION_TYPE=wayland", `XDG_CURRENT_DESKTOP=${desktop}`, `XDG_SESSION_DESKTOP=${desktop}`]);
        }

        function onAuthFailure(message: string): void {
            root.busy = false;
            root.answering = false;
            root.password = "";
            // PAM's reason when it gave one (a locked account: greetd's own failure text would hide it, and the right
            // password would look wrong until the lock ends)
            root.message = root.pamMessage || root.failureText(message);
            shake.restart();
        }

        function onError(error: string): void {
            root.busy = false;
            root.answering = false;
            root.message = error;
            Greetd.cancelSession();
        }
    }

    // failureText: greetd's failure text, which is PAM's raw code ("pam_authenticate: AUTH_ERR"), in words; anything
    // else as it came (tests/greeter-failure.sh runs this function)
    function failureText(message: string): string {
        const code = (message || "").replace(/^pam_[a-z_]+:\s*/, "").trim();
        const words = {
            "": "Wrong password",
            AUTH_ERR: "Wrong password",
            USER_UNKNOWN: "Wrong user or password",
            MAXTRIES: "Too many tries: wait a little, then try again",
            PERM_DENIED: "This account isn't allowed to log in here",
            ACCT_EXPIRED: "This account has expired",
            NEW_AUTHTOK_REQD: "The password has expired: change it in a text console (Ctrl+Alt+F2)",
            AUTHTOK_EXPIRED: "The password has expired: change it in a text console (Ctrl+Alt+F2)",
            AUTHINFO_UNAVAIL: "The password couldn't be checked",
            CRED_INSUFFICIENT: "The password couldn't be checked"
        };
        return words[code] ?? message;
    }

    // Entrance, macOS-like: the password pill comes down onto the screen from in front of it (bigger and out of focus,
    // as if close to you, shrinking and sharpening into place, slowing gradually), then the rest in turn from the centre
    // outward. Element n moves while intro goes from n * 0.25 to n * 0.25 + 1 (introT: its own 0 to 1). Started once
    // the wallpaper is there (the screen is showing by then), at most 1.5 s in without one. The lock screen has the
    // same motion (lock_intro in caelestia-overlay/patch.py): change both together
    property real intro: 0
    property bool introStarted

    function introT(n: int): real {
        return Math.max(0, Math.min(1, intro - n * 0.25));
    }

    // No fade: it shows the moment its turn starts, fully blurred
    function fallOpacity(n: int): real {
        return introT(n) > 0 ? 1 : 0;
    }

    // Out of focus while close to you, sharpening as it comes down
    function fallBlur(n: int): real {
        return Math.pow(1 - introT(n), 3);
    }

    // From 220% down to its size: fast at first, slowing gradually all the way into place
    function fallScale(n: int): real {
        return 1 + 1.2 * Math.pow(1 - introT(n), 3);
    }

    function startIntro(): void {
        if (!introStarted) {
            introStarted = true;
            introAnim.start();
        }
    }

    NumberAnimation {
        id: introAnim

        target: root
        property: "intro"
        to: 5 * 0.25 + 1
        duration: 600
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: root.startIntro()
    }

    FloatingWindow {
        id: win

        color: root.surface
        implicitWidth: 1920
        implicitHeight: 1080
        title: "Caelestia greeter"

        // Under greetd (cage) the window covers all monitors side by side: work out each
        // monitor's place in it. In a desktop preview the window is just one area.
        readonly property bool spansOutputs: Greetd.available
        readonly property var outputs: Quickshell.screens
        readonly property real originX: Math.min(...outputs.map(o => o.x))
        readonly property real originY: Math.min(...outputs.map(o => o.y))
        // The login card on an external monitor when one is connected (a docked laptop's lid may be shut, and cage
        // still lists its panel), the laptop's panel when it's alone
        readonly property var mainOutput: outputs.find(o => !/^(eDP|LVDS|DSI)/.test(o.name)) ?? outputs[0]

        function rectOf(o: var): rect {
            return spansOutputs && o ? Qt.rect(o.x - originX, o.y - originY, o.width, o.height) : Qt.rect(0, 0, width, height);
        }

        // Wallpaper on each monitor, blurred and dimmed like Caelestia's lock screen
        Repeater {
            model: win.spansOutputs ? win.outputs : [null]

            Item {
                id: wallArea

                required property var modelData
                readonly property rect r: win.rectOf(modelData)

                x: r.x
                y: r.y
                width: r.width
                height: r.height
                clip: true

                Image {
                    id: wall

                    anchors.fill: parent
                    source: root.wallpaper ? `file://${root.wallpaper}` : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                    onStatusChanged: if (status === Image.Ready || status === Image.Error) root.startIntro()
                }

                MultiEffect {
                    anchors.fill: parent
                    source: wall
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    blurMultiplier: 1
                    opacity: wall.status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 600
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(root.surface, 0.45)
                }
            }
        }

        // The monitor the login card and buttons go on
        Item {
            id: area

            readonly property rect r: win.rectOf(win.mainOutput)

            x: r.x
            y: r.y
            width: r.width
            height: r.height
        }

        // Centre card (its background comes in with the password pill, the first element)
        Rectangle {
            id: card

            // Scale with the monitor (bigger on the laptop's high-resolution screen)
            readonly property real s: Math.max(0.7, area.height / 1300)

            anchors.centerIn: area
            implicitWidth: Math.round(560 * s)
            implicitHeight: column.implicitHeight + 72 * s
            radius: 56 * s
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.alpha(root.surfaceContainer, 0.82)
                opacity: root.fallOpacity(0)
                scale: root.fallScale(0)
                layer.enabled: root.introT(0) < 1
                layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(0); blurMax: 48 }
            }

            // Tell the start script the login screen is up once its first frame is on the screen (otherwise it falls
            // back to another one): loaded but never drawn (a GPU problem) still falls back
            Connections {
                property bool sent: false

                target: sent ? null : card.Window.window
                function onFrameSwapped(): void {
                    sent = true;
                    Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-greeter-ready`]);
                }
            }

            ColumnLayout {
                id: column

                anchors.centerIn: parent
                width: parent.width - 96 * card.s
                spacing: 18 * card.s

                // Clock: hours in primary, minutes in secondary
                Row {
                    opacity: root.fallOpacity(4)
                    scale: root.fallScale(4)
                    layer.enabled: root.introT(4) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(4); blurMax: 48 }
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10 * card.s

                    Text {
                        renderType: Text.NativeRendering
                        text: Qt.formatTime(clock.date, "HH")
                        color: root.primary
                        font.family: root.font
                        font.pixelSize: 150 * card.s
                        font.weight: Font.Medium
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: Qt.formatTime(clock.date, "mm")
                        color: root.secondary
                        font.family: root.font
                        font.pixelSize: 150 * card.s
                        font.weight: Font.Medium
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -20 * card.s
                    text: Qt.formatDate(clock.date, "dddd • d MMM").toUpperCase()
                    opacity: root.fallOpacity(3)
                    scale: root.fallScale(3)
                    layer.enabled: root.introT(3) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(3); blurMax: 48 }
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: 20 * card.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }

                // Profile picture shape
                Item {
                    opacity: root.fallOpacity(2)
                    scale: root.fallScale(2)
                    layer.enabled: root.introT(2) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(2); blurMax: 48 }
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 28 * card.s
                    implicitWidth: 200 * card.s
                    implicitHeight: 190 * card.s

                    MaterialShape {
                        anchors.centerIn: parent
                        implicitSize: parent.implicitWidth
                        shape: MaterialShape.ClamShell
                        color: root.surfaceContainerHighest
                    }

                    Icon {
                        anchors.centerIn: parent
                        text: "person"
                        size: 96 * card.s
                        color: root.fgVariant
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignHCenter
                    text: root.user
                    opacity: root.fallOpacity(1)
                    scale: root.fallScale(1)
                    layer.enabled: root.introT(1) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(1); blurMax: 48 }
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: 24 * card.s
                    font.weight: Font.Medium
                }

                // Password pill
                Rectangle {
                    id: pill

                    opacity: root.fallOpacity(0)
                    scale: root.fallScale(0)
                    layer.enabled: root.introT(0) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(0); blurMax: 48 }

                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6 * card.s
                    implicitWidth: column.width * 0.9
                    implicitHeight: 64 * card.s
                    radius: height / 2
                    color: root.surfaceContainerHigh
                    border.width: input.activeFocus ? 2 : 0
                    border.color: Qt.alpha(root.primary, 0.6)

                    transform: Translate {
                        id: shakeT
                    }

                    SequentialAnimation {
                        id: shake

                        loops: 2
                        NumberAnimation { target: shakeT; property: "x"; to: -12; duration: 50 }
                        NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
                        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
                    }

                    Icon {
                        id: lockIcon

                        anchors.left: parent.left
                        anchors.leftMargin: 22 * card.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.busy ? "progress_activity" : input.echoMode === TextInput.Normal ? "visibility" : "lock"
                        size: 26 * card.s
                        color: root.message ? root.error : root.fgVariant

                        RotationAnimation on rotation {
                            running: root.busy
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: input.echoMode = input.echoMode === TextInput.Password ? TextInput.Normal : TextInput.Password
                        }
                    }

                    TextInput {
                        id: input

                        anchors.left: lockIcon.right
                        anchors.right: enter.left
                        anchors.leftMargin: 16 * card.s
                        anchors.rightMargin: 12 * card.s
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        enabled: !root.busy
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: root.fg
                        selectionColor: Qt.alpha(root.primary, 0.4)
                        font.family: root.font
                        font.pixelSize: 20 * card.s
                        font.letterSpacing: echoMode === TextInput.Password ? 4 : 0
                        clip: true
                        text: root.password
                        onTextEdited: {
                            root.password = text;
                            root.message = "";
                        }
                        onAccepted: root.login()
                        Component.onCompleted: forceActiveFocus()

                        // Text cursor in the accent colour (the default one is dark, so it didn't show), blinking
                        cursorDelegate: Rectangle {
                            width: 2 * card.s
                            radius: width / 2
                            color: root.primary

                            SequentialAnimation on opacity {
                                running: input.cursorVisible
                                loops: Animation.Infinite
                                NumberAnimation { to: 1; duration: 0 }
                                PauseAnimation { duration: 530 }
                                NumberAnimation { to: 0; duration: 120 }
                                PauseAnimation { duration: 410 }
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: "Enter your password"
                            color: Qt.alpha(root.fgVariant, 0.7)
                            font.family: root.font
                            font.pixelSize: 20 * card.s
                        }
                    }

                    // Enter button: grey circle, becomes a primary arrow once something is typed
                    Item {
                        id: enter

                        anchors.right: parent.right
                        anchors.rightMargin: 8 * card.s
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: pill.height - 16 * card.s
                        implicitHeight: implicitWidth

                        MaterialShape {
                            anchors.fill: parent
                            implicitSize: parent.implicitWidth
                            color: root.password ? root.primary : root.surfaceContainerHighest
                            shape: root.password ? MaterialShape.Arrow : MaterialShape.Circle
                            rotation: 90
                            scale: !root.password ? 1 : enterMouse.pressed ? 0.75 : enterMouse.containsMouse ? 0.95 : 0.85

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                }
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            text: "arrow_forward"
                            size: 26 * card.s
                            color: root.fgVariant
                            opacity: root.password ? 0 : 1

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 150
                                }
                            }
                        }

                        MouseArea {
                            id: enterMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.password ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.login()
                        }
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 22 * card.s
                    text: root.message
                    opacity: root.fallOpacity(1)
                    scale: root.fallScale(1)
                    layer.enabled: root.introT(1) < 1
                    layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(1); blurMax: 48 }
                    color: root.error
                    font.family: root.font
                    font.pixelSize: 15 * card.s
                }
            }
        }

        // Bottom bar: session on the left, power on the right
        RowLayout {
            opacity: root.fallOpacity(5)
            scale: root.fallScale(5)
            layer.enabled: root.introT(5) < 1
            layer.effect: MultiEffect { blurEnabled: true; blur: root.fallBlur(5); blurMax: 48 }
            anchors.left: area.left
            anchors.right: area.right
            anchors.bottom: area.bottom
            anchors.margins: 32 * card.s

            Pill {
                icon: "desktop_windows"
                label: root.session.name
                trailing: root.sessions.length > 1 ? "unfold_more" : ""
                onClicked: root.sessionIdx = (root.sessionIdx + 1) % root.sessions.length
            }

            Item {
                Layout.fillWidth: true
            }

            Pill {
                icon: "restart_alt"
                onClicked: Quickshell.execDetached(["systemctl", "reboot"])
            }

            Pill {
                icon: "power_settings_new"
                onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
            }
        }

        SystemClock {
            id: clock

            precision: SystemClock.Minutes
        }
    }

    component Icon: Text {
        renderType: Text.NativeRendering
        property real size: 24
        property real fill: 1

        font.family: root.iconFont
        font.pixelSize: size
        font.variableAxes: ({ FILL: fill })
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    component Pill: Rectangle {
        id: pillBtn

        property string icon
        property string label
        property string trailing

        signal clicked

        implicitHeight: 52 * card.s
        implicitWidth: row.implicitWidth + (label ? 40 : 28) * card.s
        radius: height / 2
        color: mouse.containsMouse ? Qt.alpha(root.surfaceContainerHighest, 0.92) : Qt.alpha(root.surfaceContainer, 0.82)

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        RowLayout {
            id: row

            anchors.centerIn: parent
            spacing: 10 * card.s

            Icon {
                text: pillBtn.icon
                size: 24 * card.s
                color: root.fg
            }

            Text {
                renderType: Text.NativeRendering
                visible: !!pillBtn.label
                text: pillBtn.label
                color: root.fg
                font.family: root.font
                font.pixelSize: 17 * card.s
            }

            Icon {
                visible: !!pillBtn.trailing
                text: pillBtn.trailing
                size: 20 * card.s
                color: root.fgVariant
            }
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pillBtn.clicked()
        }
    }
}
