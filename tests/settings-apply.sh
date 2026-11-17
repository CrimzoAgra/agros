#!/usr/bin/env bash
# The Settings app's apply (its command, from settings/shell.qml, run as the app runs it): each pending apply goes to
# dots-settings apply as one argument, whatever a set printed besides it (a line break or a quote ran as shell before),
# and one failing makes the whole fail while the others still run
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.config/quickshell/settings/shell.qml
cmd=$(sed -n "s/^ *applier.command = \[\"sh\", \"-c\", '\(.*\)', root.cli, ...root.pendingApply\];\$/\1/p" "$qml")
[[ -n $cmd ]] || fail "the Settings app's apply command not found"
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\nprintf "[%%s]" "$@" >>%s/calls; echo >>%s/calls\n[ "$2" != bad ]\n' "$t" "$t" >"$t/cli" && chmod +x "$t/cli"
sh -c "$cmd" "$t/cli" hypr $'ok\ntouch '"$t/ran" 'a "b" $(touch '"$t/ran"')' || fail "the applies failed"
[[ ! -e $t/ran ]] || fail "a set's output ran as a command"
[[ $(cat "$t/calls") == "[apply][hypr]"$'\n'"[apply][ok"$'\n'"touch $t/ran]"$'\n''[apply][a "b" $(touch '"$t/ran"')]' ]] ||
    fail "not each as one argument: $(cat "$t/calls")"
: >"$t/calls"
if sh -c "$cmd" "$t/cli" bad caelestia; then fail "a failed apply not said"; fi
[[ $(cat "$t/calls") == "[apply][bad]"$'\n'"[apply][caelestia]" ]] || fail "the apply after a failed one not run: $(cat "$t/calls")"
echo "ok settings-apply"
