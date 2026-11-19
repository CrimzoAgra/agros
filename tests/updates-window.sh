#!/usr/bin/env bash
# The Updates app's window (updates/shell.qml): "Update all", appearing where "Check again" was (nothing waiting before
# the check), under the pointer, takes no click for a moment (a double-click on "Check again" started an install)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.config/quickshell/updates/shell.qml
all=$(sed -n '/^                Button {$/,/^                }$/p' "$qml" | sed -n '/label: "Update all"/,$p')
{ grep -q 'onVisibleChanged: if (visible) justShown.restart()' <<<"$all" &&
    grep -q 'onClicked: if (!justShown.running) root.updateAll()' <<<"$all" &&
    grep -q 'interval: 1000' <<<"$all"; } ||
    fail "\"Update all\" takes a click as soon as it appears, under the pointer that clicked \"Check again\""
echo "ok updates-window"
