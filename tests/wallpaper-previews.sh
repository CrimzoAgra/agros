#!/usr/bin/env bash
# The previews with the wallpaper behind their windows (the Super+Tab switcher's, the bar's workspace preview, window
# peek's) show the one Caelestia shows now: by its own file (Caelestia's path.txt, its Wallpapers service), not by the
# fixed link to it (~/.local/state/caelestia/wallpaper/current), whose URL never changes, so the image cache kept the
# old picture after a change; and a video wallpaper's still (thumbnail.jpg) only for that one, a new one tried first
set -euo pipefail
. "$(dirname "$0")/lib.sh"
for f in "$here"/.config/quickshell/*/shell.qml "$here"/.local/share/caelestia-overlay/*.qml; do
    if grep -n 'source:.*wallpaper/current' "$f"; then fail "${f#"$here"/} shows the wallpaper by its fixed link"; fi
    if grep -n 'source = .*thumbnail' "$f"; then fail "${f#"$here"/} keeps the video wallpaper's still for good"; fi
done
s=$here/.config/quickshell/switcher/shell.qml
{ grep -q 'wallpaper/path.txt`' "$s" && grep -q 'watchChanges: true' "$s" && grep -q 'source: .*root.wallpaper' "$s"; } ||
    fail "the switcher's previews don't follow Caelestia's wallpaper"
grep -q 'Wallpapers.current' "$here/.local/share/caelestia-overlay/WorkspacePreview.qml" ||
    fail "the workspace preview doesn't follow Caelestia's wallpaper"
echo "ok wallpaper-previews"
