#!/usr/bin/env bash
# The Updates app's window (updates/shell.qml): "Update all", appearing where "Check again" was (nothing waiting before
# the check), under the pointer, takes no click for a moment (a double-click on "Check again" started an install); a
# version cut off shows whole while hovered; the log's errors red, but not one mirror's missing file (the next mirror had it)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.config/quickshell/updates/shell.qml
all=$(sed -n '/^                Button {$/,/^                }$/p' "$qml" | sed -n '/label: "Update all"/,$p')
{ grep -q 'onVisibleChanged: if (visible) justShown.restart()' <<<"$all" &&
    grep -q 'onClicked: if (!justShown.running) root.updateAll()' <<<"$all" &&
    grep -q 'interval: 1000' <<<"$all"; } ||
    fail "\"Update all\" takes a click as soon as it appears, under the pointer that clicked \"Check again\""
# A version too long for its column (cut at the end: 2.44+r50+g1848099f063e-3 → 2.44+r78+g…) shows whole while its row
# is hovered
grep -q 'Layout.maximumWidth: hover.hovered ? row.width - 120 : 260' <<<"$(grep -B6 \
    'text: (row.modelData.old ? row.modelData.old + "  →  " : "") + row.modelData.new' "$qml")" || fail "a long version cut off for good"
if command -v node >/dev/null; then
    fn=$(sed -n '/^    function isError(line: string): bool {$/,/^    }$/p' "$qml" | sed 's/(line: string): bool {/(line) {/')
    [[ -n $fn ]] || fail "the log's error colouring not found"
    red=$(node -e "$fn
console.log([\"error: failed retrieving file 'glibc-2.44+r78+gfcfb867c58ab-1-x86_64_v3.pkg.tar.zst' from cdn77.cachyos.org : The requested URL returned error: 404\",
    'error: failed to retrieve some files', 'error: failed to commit transaction (conflicting files)', ' -> error: build failed',
    'upgrading libgpg-error...', ':: Retrieving packages...'].map(isError).join(' '))")
    [[ $red == "false true true true false false" ]] ||
        fail "the log's red lines: $red (want: false true true true false false: a mirror's missing file not red, real errors red)"
else
    skipped "no node: the log's colours not checked"
fi
echo "ok updates-window"
