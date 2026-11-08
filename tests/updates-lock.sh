#!/usr/bin/env bash
# The Updates app's "Update all" (its command, from updates/shell.qml, run as the app runs it): one update at a time,
# and once it has ended, the next click runs a new one: a background job the update left running (git gc after paru's
# AUR pulls) doesn't keep its lock, taking the next click for "an update started earlier is still running"
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cmd=$(sed -n "s/^ *command: \[\"sh\", \"-c\", '\(.*\)',\$/\1/p" "$here/.config/quickshell/updates/shell.qml")
[[ $cmd == *flock* ]] || fail "the Updates app's command not found"
# The update: says so, leaves a job running in the background (with every descriptor it was given), ends
cat >"$t/update" <<'S'
#!/bin/sh
echo "updating"
sleep 5 >/dev/null 2>&1 &
exit 0
S
chmod +x "$t/update"
out=$(timeout 20 sh -c "$cmd" "$t/update" "$t/log" 2>&1) || fail "the update failed: $out"
[[ $out == *updating* ]] || fail "the update didn't run: $out"
out=$(timeout 20 sh -c "$cmd" "$t/update" "$t/log" 2>&1) || fail "the second update failed: $out"
[[ $out != *"still running"* ]] || fail "an update that had ended still held the lock (its background job): $out"
echo "ok updates-lock"
