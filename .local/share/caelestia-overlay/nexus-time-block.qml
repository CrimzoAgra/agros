
        // ---- caelestia-overlay: the system clock (timedatectl; changing it asks for your password, through polkit) ----
        Item {
            id: clock

            property string zone
            property bool ntp
            property bool synced
            property var zones: []
            property string now
            property string stamp // (as the date and time field takes it)
            property string zoneTyped
            property string timeTyped
            // The time zone from your location (~/.local/bin/timezone-auto: on while its flag file is there)
            property bool autoZone
            readonly property string autoZoneScript: `${Quickshell.env("HOME")}/.local/bin/timezone-auto`
            readonly property string place: GlobalConfig.services.weatherLocation

            // (a new weather location: the zone follows it)
            onPlaceChanged: if (autoZone) Quickshell.execDetached([autoZoneScript])

            // timedatectl again shortly after a change (it applies it in the background), then every few seconds
            function refresh(): void {
                show.running = true;
                again.restart();
            }
            function run(args: var): void {
                Quickshell.execDetached(["timedatectl", ...args]);
                refresh();
            }

            visible: false // (no place in the layout: only the workings)

            Process {
                id: show

                command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP", "-p", "NTPSynchronized", "--value"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const v = text.split("\n");
                        clock.zone = v[0] ?? "";
                        clock.ntp = v[1] === "yes";
                        clock.synced = v[2] === "yes";
                    }
                }
            }

            Process {
                running: true
                command: ["timedatectl", "list-timezones"]
                stdout: StdioCollector {
                    onStreamFinished: clock.zones = text.split("\n").filter(z => z)
                }
            }

            Timer {
                running: root.visible
                repeat: true
                triggeredOnStart: true
                interval: 1000
                onTriggered: {
                    // (the day short, the time with its zone's short name: what the time zone row changes)
                    const d = new Date();
                    clock.now = `${d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)}  ${d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)} ${Qt.formatDateTime(d, "t")}`;
                    clock.stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
                    if (!show.running && new Date().getSeconds() % 5 === 0)
                        show.running = true;
                }
            }

            Timer {
                id: again

                interval: 1500
                onTriggered: show.running = true
            }

            Process {
                running: true
                command: ["test", "-e", `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/agros/timezone-auto`]
                onExited: code => clock.autoZone = code === 0
            }

            Component.onCompleted: show.running = true
        }

        InfoRow {
            label: Tr.tr("Time")
            subtext: !clock.ntp ? Tr.tr("Set by hand") : clock.synced ? Tr.tr("In sync with internet time") : Tr.tr("Not in sync yet")
            value: clock.now
        }

        ToggleRow {
            text: Tr.tr("Set the time automatically")
            subtext: Tr.tr("From time servers on the internet (NTP)")
            checked: clock.ntp
            onToggled: {
                clock.run(["set-ntp", checked ? "true" : "false"]);
                checked = Qt.binding(() => clock.ntp); // (what the system says, once it has applied it)
            }
        }

        SuggestRow {
            visible: !clock.ntp
            first: false
            last: false
            icon: "schedule"
            label: Tr.tr("Date and time")
            subtext: Tr.tr("Type it, then Enter")
            placeholderText: "YYYY-MM-DD HH:MM" // (on the field's border, as the location's "Automatic")
            value: clock.stamp
            onAccepted: t => {
                if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(t.trim()))
                    clock.run(["set-time", t.trim() + ":00"]);
            }
        }

        ToggleRow {
            text: Tr.tr("Set the time zone automatically")
            subtext: Tr.tr("From the weather location, or your internet address when that's automatic")
            checked: clock.autoZone
            onToggled: {
                clock.autoZone = checked;
                Quickshell.execDetached([clock.autoZoneScript, checked ? "on" : "off"]);
                checked = Qt.binding(() => clock.autoZone);
            }
        }

        // The time zone: typed and picked from the system's list (a city's name finds it: "lisbon", "new york"); shown
        // only, while it's set automatically
        SuggestRow {
            first: false
            enabled: !clock.autoZone
            icon: "public"
            label: Tr.tr("Time zone")
            subtext: clock.autoZone ? Tr.tr("Set from your location") : Tr.tr("Type a city to find it")
            placeholderText: Tr.tr("Region/City")
            value: clock.zone
            suggestions: {
                const q = clock.zoneTyped.toLowerCase().replace(/ /g, "_");
                return q.length < 2 ? [] : clock.zones.filter(z => z.toLowerCase().includes(q)).slice(0, 6).map(z => ({
                            text: z.split("/").pop().replace(/_/g, " "),
                            subtext: z
                        }));
            }
            onTyped: t => clock.zoneTyped = t.trim()
            onAccepted: (t, i) => {
                const z = i >= 0 ? suggestions[i].subtext : clock.zones.find(z => z.toLowerCase() === t.trim().toLowerCase());
                if (z && z !== clock.zone)
                    clock.run(["set-timezone", z]);
            }
        }
