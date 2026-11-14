#!/usr/bin/env bash
# qs-running: a Quickshell running whose "qs list --all" entry has one of the texts in it; none of them, or qs failing
# (not installed, no instance): not running
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
qs() { printf '#!/bin/sh\n%s\n' "$1" >"$t/bin/qs"; chmod +x "$t/bin/qs"; }
running() { PATH=$t/bin:$PATH "$here/.local/bin/qs-running" "$@"; }
# (qs list's own layout, two instances; a long one, as qs's output is read whole: no SIGPIPE taken for "not running")
qs 'echo "Instance a:"; echo "  Process ID: 1"; echo "  Config path: /home/u/.config/quickshell/caelestia/shell.qml"
echo "Instance b:"; echo "  Config path: /home/u/.config/quickshell/widgets/shell.qml"; seq 100000'
running /quickshell/caelestia/shell.qml || fail "a running config not found"
running /nothing "Config path: /home/u/.config/quickshell/widgets/shell.qml" || fail "the second text not looked for"
running /quickshell/switcher/shell.qml && fail "a config not running found"
qs 'echo "  Config path: /x/quickshell/caelestia/shell.qml"; exit 1'
running /quickshell/caelestia/shell.qml || fail "qs's own exit status taken over what it listed"
qs 'exit 1'
running /quickshell/caelestia/shell.qml && fail "qs failing (nothing listed) taken for running"
echo "ok qs-running"
