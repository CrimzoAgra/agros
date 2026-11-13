#!/usr/bin/env bash
# caelestia-overlay with a Caelestia running from the overlay (a Caelestia update from the Updates app: its pacman hook
# runs it for each user inside the session): handed to caelestia-restart --rebuild (it stops the shell, rebuilds, starts
# it again), the folder not swapped under the running shell (Hyprland dropped it, nothing started it again); with
# CAELESTIA_REBUILDING (that rebuild itself) or no shell from it, built as before
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[[ -d /etc/xdg/quickshell/caelestia ]] || { echo "skip caelestia-overlay-live (Caelestia not installed)"; exit 0; }
h=$t/home sb=$t/bin dst=$t/home/.config/quickshell/caelestia
mkdir -p "$h/.local/bin" "$h/.local/share" "$dst" "$sb"
ln -s "$here/.local/share/caelestia-overlay" "$h/.local/share/caelestia-overlay"
touch "$dst/shell.qml"; inode=$(stat -c %i "$dst")
# (running while $t/running is there)
printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && [ -e "%s" ] && echo "  Config path: %s/shell.qml"\nexit 0\n' "$t/running" "$dst" >"$sb/qs"
touch "$t/running"
printf '#!/bin/sh\necho "restart $*" >>"%s"\n' "$t/calls" >"$h/.local/bin/caelestia-restart"
chmod +x "$sb/qs" "$h/.local/bin/caelestia-restart"
run() { env -i HOME="$h" PATH="$sb:/usr/bin" "$@" "$here/.local/bin/caelestia-overlay" 2>&1; }
out=$(run) || fail "with Caelestia running from it: $out"
[[ $(cat "$t/calls" 2>/dev/null) == "restart --rebuild" ]] || fail "not handed to caelestia-restart --rebuild: $out"
[[ $(stat -c %i "$dst") == "$inode" ]] || fail "the folder swapped under the running Caelestia"
# A handover whose rebuild failed (3: the shell started again all the same): not built again here under it
printf '#!/bin/sh\necho "restart $*" >>"%s"\nexit 3\n' "$t/calls" >"$h/.local/bin/caelestia-restart"; rm -f "$t/calls"
out=$(run) && fail "a failed handed-over rebuild reported success: $out"
[[ $(stat -c %i "$dst") == "$inode" ]] || fail "built again under the shell restarted by a failed handed-over rebuild"
printf '#!/bin/sh\necho "restart $*" >>"%s"\n' "$t/calls" >"$h/.local/bin/caelestia-restart"; rm -f "$t/calls"
# Waiting on the lock while a restart holds it (its shell stopped, then started again): handed over once it's up, the
# folder not swapped under the shell just started
rm "$t/running"
( exec 9>"$dst.lock"; flock 9; sleep 1; touch "$t/running" ) & sleep 0.2
out=$(run) || fail "after a restart: $out"
wait
[[ $(cat "$t/calls" 2>/dev/null) == "restart --rebuild" && $(stat -c %i "$dst") == "$inode" ]] ||
    fail "a rebuild that waited for a restart's lock swapped the folder under its new shell: $out"
rm -f "$t/calls"
# caelestia-restart's own run (the shell stopped by then): built
rm -f "$t/calls"
out=$(run CAELESTIA_REBUILDING=1 DOTS_SETTINGS=/bin/false nice -n 19) || true
[[ ! -e $t/calls && $(stat -c %i "$dst") != "$inode" ]] || fail "caelestia-restart's own rebuild didn't build: $out"
echo "ok caelestia-overlay-live"
