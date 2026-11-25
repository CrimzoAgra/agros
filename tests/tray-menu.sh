#!/usr/bin/env bash
# tray-menu <id>: the tray icon with that Id (of those the tray lists) asked for its own menu, at the pointer; the
# others not, nor one with an Id that only starts the same
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
stub hyprctl 'echo "{\"x\": 1930, \"y\": 12}"'
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub busctl "echo \"busctl \$*\" >>$t/calls"'
case "$*" in
    *RegisteredStatusNotifierItems) echo "as 3 \":1.80/StatusNotifierItem\" \":1.81/StatusNotifierItem\" \":1.95/org/ayatana/NotificationItem/x\"" ;;
    "--user get-property :1.80 /StatusNotifierItem "*" Id") echo "s \"wine-epic-2\"" ;;
    "--user get-property :1.81 /StatusNotifierItem "*" Id") echo "s \"wine-epic\"" ;;
    "--user get-property :1.95 /org/ayatana/NotificationItem/x "*" Id") echo "s \"other\"" ;;
esac'
PATH=$t/bin:$PATH "$here/.local/bin/tray-menu" wine-epic
grep -qx 'busctl --user call :1.81 /StatusNotifierItem org.kde.StatusNotifierItem ContextMenu ii 1930 12' "$t/calls" ||
    fail "the menu not asked of wine-epic's icon at the pointer: $(cat "$t/calls")"
[[ $(grep -c ' call ' "$t/calls") == 1 ]] || fail "another icon's menu asked too: $(cat "$t/calls")"
echo "ok tray-menu"
