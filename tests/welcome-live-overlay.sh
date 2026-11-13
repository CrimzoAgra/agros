#!/usr/bin/env bash
# agros-welcome's Caelestia step and a Caelestia already running:
# - on the overlay (caelestia-start built it at this login): left alone, nothing rebuilt under it (the folder swapped
#   under the running shell got it dropped by Hyprland, and with the overlay unchanged nothing restarted it)
# - without your changes (caelestia-start's build failed: the copy it left, its state file saying so, or Caelestia from
#   /etc/xdg): caelestia-restart --rebuild (stopped, rebuilt, started), never a build under it
# - none running: built, unless caelestia-start just built it (its shell not up yet)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
h=$t/home sb=$t/bin; mkdir -p "$h/.local/bin" "$h/.config/quickshell/caelestia" "$h/.local/state/agros" "$sb"
touch "$h/.local/state/agros/wallpaper-set"
printf '#!/bin/sh\necho built >>"%s"\n' "$t/calls" >"$h/.local/bin/caelestia-overlay"
# (qs list's own format; the file says where the running one is from: the overlay, or Caelestia's own in /etc/xdg)
printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && [ -e "%s" ] && echo "  Config path: $(cat "%s")"\nexit 0\n' "$t/running" "$t/running" >"$sb/qs"
printf '#!/bin/sh\necho "hyprctl $*" >>"%s"\n' "$t/calls" >"$sb/hyprctl"
chmod +x "$sb"/* "$h/.local/bin/caelestia-overlay"
run() { rm -f "$t/calls"; env -i HOME="$h" PATH="$sb:/usr/bin" bash -c 'st=$HOME/.local/state/agros; source "$1/.local/bin/agros-welcome"; caelestia_setup' _ "$here" </dev/null; }
calls() { cat "$t/calls" 2>/dev/null; }
skipped=$h/.local/state/caelestia-overlay-skipped

ours=$h/.config/quickshell/caelestia/shell.qml
echo "$ours" >"$t/running"; touch "$ours"
out=$(run) || fail "running: $out"
[[ -z $(calls) ]] || fail "Caelestia running on the overlay: not left alone: $(calls)"

echo "The overlay failed, Caelestia runs without your changes: boom" >"$skipped"
out=$(run) || fail "failed build: $out"
grep -q -- 'caelestia-restart --rebuild' "$t/calls" && ! grep -q '^built$' "$t/calls" ||
    fail "Caelestia on a failed build's copy: not caelestia-restart --rebuild (or built under it): $(calls)"
rm "$skipped" "$h/.config/quickshell/caelestia/shell.qml"
echo /etc/xdg/quickshell/caelestia/shell.qml >"$t/running"
out=$(run) || fail "from /etc/xdg: $out"
grep -q -- 'caelestia-restart --rebuild' "$t/calls" && ! grep -q '^built$' "$t/calls" ||
    fail "Caelestia without the overlay: not caelestia-restart --rebuild: $(calls)"
# ...and still from /etc/xdg with a good overlay there now (built by an update's hook since): not taken for ours
touch "$ours"
out=$(run) || fail "from /etc/xdg, overlay there: $out"
grep -q -- 'caelestia-restart --rebuild' "$t/calls" || fail "Caelestia from /etc/xdg taken for one on the overlay: $(calls)"
rm "$ours"
# A failure returned (the step tried again at the next login, not marked done): the dispatch refused, nothing running
printf '#!/bin/sh\nexit 1\n' >"$sb/hyprctl"
run >/dev/null && fail "the restart not dispatched, yet the step reported done"
printf '#!/bin/sh\necho "hyprctl $*" >>"%s"\n' "$t/calls" >"$sb/hyprctl"

rm "$t/running"
touch "$h/.config/quickshell/caelestia/shell.qml"
out=$(run) || fail "built, not running yet: $out"
[[ -z $(calls) ]] || fail "built by caelestia-start, its shell not up yet: built again under it: $(calls)"
rm "$h/.config/quickshell/caelestia/shell.qml"
out=$(run) || fail "not running: $out"
[[ $(calls) == built ]] || fail "no Caelestia running: the overlay not built (only): $(calls)"
echo "ok welcome-live-overlay"
