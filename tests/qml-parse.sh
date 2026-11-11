#!/usr/bin/env bash
# Every QML file parses (Qt's qmllint, syntax errors only: the imports of Quickshell and Caelestia it can't resolve here
# aren't errors): the separate shells (widgets, switcher, settings, updates) and their shared colours (common/), the
# overlay's own components, and Caelestia's files as the overlay patches them (a patch that fits its anchors can still
# leave broken QML, which only shows as a shell that doesn't start)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
lint=$(command -v /usr/lib/qt6/bin/qmllint qmllint6 2>/dev/null | head -1) || true
[[ -n $lint ]] || { echo "skip qml-parse (no Qt 6 qmllint)"; exit 0; }
syntax() {
    local out
    out=$("$lint" "$1" 2>&1 | grep -A2 '\[syntax\]' || true)
    [[ -z $out ]] || fail "${1#"$t"/} doesn't parse: $out"
}

for f in "$here"/.config/quickshell/*/shell.qml "$here"/.config/quickshell/common/*.qml "$here"/.local/share/caelestia-overlay/*.qml; do
    [[ ${f##*/} == *-block.qml ]] && continue  # (fragments patch.py puts in Caelestia's files: checked there, below)
    syntax "$f"
done

[[ -d /etc/xdg/quickshell/caelestia ]] || { echo "ok qml-parse (Caelestia not installed: its patched files not checked)"; exit 0; }
# Every feature on, whatever your Settings app says
printf '#!/bin/sh\necho "{}"\n' >"$t/dots-settings"; chmod +x "$t/dots-settings"
cp -as /etc/xdg/quickshell/caelestia "$t/caelestia"
DOTS_SETTINGS=$t/dots-settings python3 "$here/.local/share/caelestia-overlay/patch.py" /etc/xdg/quickshell/caelestia "$t/caelestia" >/dev/null ||
    true  # (a patch that no longer fits is tests/caelestia-overlay.sh's to report)
n=0
while IFS= read -r f; do
    syntax "$f"
    n=$((n + 1))
done < <(find "$t/caelestia" -type f -name '*.qml')
((n > 10)) || fail "only $n patched QML files: the overlay didn't run"
echo "ok qml-parse"
