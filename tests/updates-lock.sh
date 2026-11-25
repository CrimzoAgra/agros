#!/usr/bin/env bash
# Settings' Updates page's "Update all" (the command its unit runs, from caelestia-overlay's AgrosUpdates.qml, run as
# the unit runs it): one update at a time, and once it has ended, the next click runs a new one: a background job the
# update left running (git gc after paru's AUR pulls) doesn't keep its lock, taking the next click for "an update
# started earlier is still running"
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
cmd=$(sed -n "s/^ *'\(exec 9>\"\$1.lock\";.*\)'\]\$/\1/p" "$here/.local/share/caelestia-overlay/AgrosUpdates.qml")
[[ $cmd == *flock* ]] || fail "the Updates page's update command not found"
# The update: says so, leaves a job running in the background (with every descriptor it was given), ends
cat >"$t/update" <<'S'
#!/bin/sh
echo "updating"
sleep 30 >/dev/null 2>&1 &
echo $! >>"$(dirname "$0")/jobs"
exit 0
S
chmod +x "$t/update"
timeout 20 sh -c "$cmd" "$t/update" "$t/log" || fail "the update's command failed"
[[ $(cat "$t/log") == updating && $(cat "$t/log.status") == 0 ]] || fail "the update didn't run: $(cat "$t/log")"
# (the page's "running": the lock held; ended, it's free though the background job runs on)
flock -n "$t/log.lock" true || fail "an update that had ended still held the lock (its background job)"
timeout 20 sh -c "$cmd" "$t/update" "$t/log" || fail "the second update's command failed"
[[ $(cat "$t/log") == $'updating\nupdating' ]] || fail "the second update didn't run: $(cat "$t/log")"
xargs kill <"$t/jobs" 2>/dev/null || true  # (its background jobs)
echo "ok updates-lock"
