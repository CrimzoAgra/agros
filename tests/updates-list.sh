#!/usr/bin/env bash
# The Updates app's list (its command, from updates/shell.qml, run as the app runs it): its last line says whether the
# list could be made, and a list that couldn't (update-apps missing, or broken) shows as that, not as "Nothing to
# update" with nothing listed
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.config/quickshell/updates/shell.qml
cmd=$(sed -n "s/^ *command: \[\"sh\", \"-c\", '\(.*\)', root.script\]\$/\1/p" "$qml" | grep -- --list) ||
    fail "the Updates app's list command not found"
printf '#!/bin/sh\nprintf "system\tfoo\t1\t2\n"\n' >"$t/list" && chmod +x "$t/list"
[[ $(sh -c "$cmd" "$t/list") == $'system\tfoo\t1\t2\nend 0' ]] || fail "a list made: $(sh -c "$cmd" "$t/list")"
printf '#!/bin/sh\nexit 3\n' >"$t/broken" && chmod +x "$t/broken"
[[ $(sh -c "$cmd" "$t/broken") == "end 3" ]] || fail "a list that failed: $(sh -c "$cmd" "$t/broken")"
[[ $(sh -c "$cmd" "$t/missing" 2>/dev/null) == "end 127" ]] || fail "a missing update-apps: $(sh -c "$cmd" "$t/missing" 2>&1)"
# ...read by the app as such: nothing listed, and said
{ grep -q 'root.listFailed = !/^end 0$/m.test(text);' "$qml" &&
    grep -q 'root.items = root.listFailed ? \[\] :' "$qml" &&
    grep -q ': root.listFailed ? "Couldn'"'"'t check for updates"' "$qml" &&
    grep -q 'text: root.listFailed ? "Couldn'"'"'t check: update-apps --list failed' "$qml"; } ||
    fail "a list that failed not shown as one"
# Offline (update-kinds' "offline" line, nothing else listed): not "Everything is up to date" in the header
{ grep -q ': root.offline ? "Couldn'"'"'t check for updates"' "$qml" &&
    grep -q 'root.pending.length ? "system_update" : root.offline ? "error" : "verified"' "$qml"; } ||
    fail "an offline check shown as up to date"
echo "ok updates-list"
