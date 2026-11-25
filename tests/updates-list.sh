#!/usr/bin/env bash
# Settings' Updates page's list (its command, from caelestia-overlay's AgrosUpdates.qml, run as the page runs it): its
# last line says whether the list could be made, and a list that couldn't (update-apps missing, or broken) shows as
# that, not as "Nothing to update" with nothing listed
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.local/share/caelestia-overlay/AgrosUpdates.qml
cmd=$(sed -n "s/^ *command: \[\"sh\", \"-c\", '\(.*\)', root.script, root.listFile\]\$/\1/p" "$qml" | grep -- --list) ||
    fail "the Updates app's list command not found"
printf '#!/bin/sh\nprintf "system\tfoo\t1\t2\n"\n' >"$t/list" && chmod +x "$t/list"
[[ $(sh -c "$cmd" "$t/list") == $'system\tfoo\t1\t2\nend 0' ]] || fail "a list made: $(sh -c "$cmd" "$t/list")"
printf '#!/bin/sh\nexit 3\n' >"$t/broken" && chmod +x "$t/broken"
[[ $(sh -c "$cmd" "$t/broken") == "end 3" ]] || fail "a list that failed: $(sh -c "$cmd" "$t/broken")"
[[ $(sh -c "$cmd" "$t/missing" 2>/dev/null) == "end 127" ]] || fail "a missing update-apps: $(sh -c "$cmd" "$t/missing" 2>&1)"
# Opened from a check's notification (UPDATES_LIST): what it found shown, update-apps not run again, the file removed;
# one older than 15 minutes checked anew (and removed too)
printf 'system\tbar\t1\t2\n' >"$t/found"
[[ $(sh -c "$cmd" "$t/broken" "$t/found") == $'system\tbar\t1\t2\nend 0' && ! -e $t/found ]] ||
    fail "a check's list not shown as it was, or checked again"
printf 'system\tbar\t1\t2\n' >"$t/found" && touch -d '20 minutes ago' "$t/found"
[[ $(sh -c "$cmd" "$t/list" "$t/found") == $'system\tfoo\t1\t2\nend 0' && ! -e $t/found ]] ||
    fail "a check's list from 20 minutes ago shown, not checked anew"
grep -q 'root.listFile = "";' "$qml" || fail "the check's list used again after an update"
# One that hangs: failed at its time limit (1 s here, not 10 minutes), the part it started in the background too (it
# kept the output open, and the app waited on it for good)
[[ $cmd == *"timeout 10m "* ]] || fail "the list has no time limit: $cmd"
printf '#!/bin/sh\nsleep 60 &\nsleep 60\n' >"$t/hangs" && chmod +x "$t/hangs"
out=$(timeout 20 sh -c "${cmd/timeout 10m /timeout 1 }" "$t/hangs") || true
[[ $out == "end 124" ]] || fail "a list that hangs not ended at its time limit: $out"
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
# An account that can't sudo (not in wheel): the list, said that an administrator installs them, no "Update all"
# (it only failed at sudo), nor the "Update now" notification's start
{ grep -q 'command: \["id", "-nG"\]' "$qml" && grep -q 'root.admin = ` ${text.trim()} `.includes(" wheel ")' "$qml" &&
    grep -q ': !root.admin && root.pending.length ? "An administrator has to install these updates"' "$qml" &&
    grep -q 'visible: root.admin && root.pending.length > 0 || root.phase === "updating"' "$qml" &&
    grep -q 'if (root.pending.length && root.admin)' "$qml"; } ||
    fail "an account that can't sudo still offered \"Update all\", or not told why"
echo "ok updates-list"
