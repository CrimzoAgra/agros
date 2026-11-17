#!/usr/bin/env bash
# The Settings, Updates and switcher apps' colours (common/Scheme.qml's c(name)): every name they ask for has a fallback,
# Caelestia's dark scheme, for until its scheme.json has loaded or when there's none (a name without one was "#undefined",
# no colour: drawn black on the dark window, a note under a setting unreadable)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qs=$here/.config/quickshell
fallback=$(sed -n '/readonly property var fallback: ({/,/})/p' "$qs/common/Scheme.qml" | sed -n 's/^ *\([A-Za-z]*\): "[0-9a-f]\{6\}",\{0,1\}$/\1/p')
[[ -n $fallback ]] || fail "Scheme.qml's fallback colours not found"
for name in $(grep -ohE '\bc\("[A-Za-z]+"\)' "$qs"/*/shell.qml "$qs"/common/*.qml | sed 's/^c("//; s/")$//' | sort -u); do
    grep -qx "$name" <<<"$fallback" || fail "c(\"$name\") has no fallback colour in common/Scheme.qml"
done
echo "ok qs-colours"
