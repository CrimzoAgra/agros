
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

        // The time zone: typed and picked from the system's list (a city's name finds it: "lisbon", "new york")
        SuggestRow {
            first: false
            icon: "public"
            label: Tr.tr("Time zone")
            subtext: Tr.tr("Type a city to find it")
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
