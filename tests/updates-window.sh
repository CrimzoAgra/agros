#!/usr/bin/env bash
# Settings' Updates page (caelestia-overlay's AgrosUpdates.qml): "Update all", appearing where "Check again" was
# (nothing waiting before the check), under the pointer, takes no click for a moment (a double-click on "Check again"
# started an install); a version cut off shows whole while hovered; "Restart" after an update asks for a second click;
# the log's errors red, but not one mirror's missing file (the next mirror had it). And the launchers that open it
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
qml=$here/.local/share/caelestia-overlay/AgrosUpdates.qml
# (the button holding k: from its "IconTextButton {" to its closing brace)
button() {
    awk -v k="$1" '/^ *IconTextButton \{$/ && !on { b = ""; on = 1; d = 0 }
        on { b = b $0 "\n"; d += gsub(/\{/, "{") - gsub(/\}/, "}"); if (d == 0) { if (index(b, k)) printf "%s", b; on = 0 } }' "$qml"
}
all=$(button 'text: "Update all"')
{ grep -q 'onVisibleChanged: if (visible) justShown.restart()' <<<"$all" &&
    grep -q 'onClicked: if (!justShown.running) root.updateAll()' <<<"$all" &&
    grep -q 'interval: 1000' <<<"$all"; } ||
    fail "\"Update all\" takes a click as soon as it appears, under the pointer that clicked \"Check again\""
# "Restart", shown after an update where "Update all" was, under the pointer: reboots only on a second click
restart=$(button 'icon: "restart_alt"')
{ grep -q 'visible: root.phase === "done"' <<<"$restart" &&
    grep -q 'if (confirm.running)' <<<"$restart" && grep -q '"systemctl", "reboot"' <<<"$restart" &&
    grep -q 'confirm.restart();' <<<"$restart"; } || fail "\"Restart\" reboots on a single click, or isn't there after an update"
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
# The launchers: Updates (the Super menu's "Update apps": ~/.local/bin/updates) opens Settings at its Updates page, and
# the Settings entry Settings (Caelestia's Nexus, AgrOS's pages in it)
stub qs 'echo "qs $*" >>"$T/calls"'
T=$t PATH=$t/bin:$PATH "$here/.local/bin/updates"
[[ $(cat "$t/calls") == 'qs -c caelestia ipc call nexus openPage update' ]] ||
    fail "the Updates launcher doesn't open Settings at Updates: $(cat "$t/calls")"
grep -qx 'Exec=qs -c caelestia ipc call nexus open' "$here/.local/share/applications/desktop-settings.desktop" ||
    fail "the Settings entry doesn't open Nexus"
# (the old Updates entry hidden: a copy in a home from before is replaced by it, agros-links, and leaves the Super menu)
grep -qx 'Hidden=true' "$here/.local/share/applications/updates.desktop" || fail "the old Updates entry still shown"
echo "ok updates-window"
