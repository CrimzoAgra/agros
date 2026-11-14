#!/usr/bin/env bash
# caelestia-overlay with a Caelestia running from the overlay (a Caelestia update from the Updates app: its pacman hook
# runs it for each user inside the session): handed to caelestia-restart --rebuild (it stops the shell, rebuilds, starts
# it again), the folder not swapped under the running shell (Hyprland dropped it, nothing started it again); with
# CAELESTIA_REBUILDING (that rebuild itself) or no shell from it, built as before
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
[[ -d /etc/xdg/quickshell/caelestia ]] || { echo "skip caelestia-overlay-live (Caelestia not installed)"; exit 0; }
h=$t/home sb=$t/bin dst=$t/home/.config/quickshell/caelestia
mkdir -p "$h/.local/bin" "$h/.local/share" "$dst" "$sb"
ln -s "$here/.local/share/caelestia-overlay" "$h/.local/share/caelestia-overlay"
touch "$dst/shell.qml"; inode=$(stat -c %i "$dst")
# (running while $t/running is there)
printf '#!/bin/sh\n[ "$1 $2" = "list --all" ] && [ -e "%s" ] && echo "  Config path: %s/shell.qml"\nexit 0\n' "$t/running" "$dst" >"$sb/qs"
touch "$t/running"
# (the scripts it runs are the ones beside it: all of them there, caelestia-restart stubbed)
cp -r "$here/.local/bin/." "$h/.local/bin/"
printf '#!/bin/sh\necho "restart $*" >>"%s"\n' "$t/calls" >"$h/.local/bin/caelestia-restart"
# No game open (Hyprland's windows, game-focus --game-open: $t/game says one is); no user manager (a run handed to it
# would be your real session's): the detached fallback
printf '#!/bin/sh\n[ -e "%s" ] && echo "[{\\"tags\\": [\\"game\\"]}]" || echo "[]"\n' "$t/game" >"$sb/hyprctl"
printf '#!/bin/sh\nexit 1\n' >"$sb/systemd-run"
# (a skipped change's note: to no real notification server)
printf '#!/bin/sh\nexit 0\n' >"$sb/notify-send"
chmod +x "$sb/qs" "$sb/hyprctl" "$sb/systemd-run" "$sb/notify-send" "$h/.local/bin/caelestia-restart"
# (lib.sh's runtime folder and bus kept through env -i: without them it fell back on your real session's bus)
run() {
    env -i HOME="$h" PATH="$sb:/usr/bin" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" "$@" "$h/.local/bin/caelestia-overlay" 2>&1
}
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
# A restart that failed (1: hyprctl couldn't reach Hyprland) with the shell still running: not built under it
printf '#!/bin/sh\necho "restart $*" >>"%s"\nexit 1\n' "$t/calls" >"$h/.local/bin/caelestia-restart"; rm -f "$t/calls"
out=$(run) && fail "a failed restart with the shell still running reported success: $out"
[[ $(stat -c %i "$dst") == "$inode" ]] || fail "built under the shell a failed restart left running"
# caelestia-restart's own run (the shell stopped by then): built
rm -f "$t/calls"
out=$(run CAELESTIA_REBUILDING=1 DOTS_SETTINGS=/bin/false nice -n 19) || true
[[ ! -e $t/calls && $(stat -c %i "$dst") != "$inode" ]] || fail "caelestia-restart's own rebuild didn't build: $out"
# A restart that failed with the shell gone by then: built here (the build just made forgotten: an unchanged one isn't
# built again, below)
rm -f "$dst/.agros-built"
inode=$(stat -c %i "$dst")
printf '#!/bin/sh\necho "restart $*" >>"%s"\nrm -f "%s"\nexit 1\n' "$t/calls" "$t/running" >"$h/.local/bin/caelestia-restart"; rm -f "$t/calls"
touch "$t/running"
out=$(run DOTS_SETTINGS=/bin/false nice -n 19) || true
[[ -e $t/calls && $(stat -c %i "$dst") != "$inode" ]] || fail "a failed restart with the shell gone didn't build: $out"
# Nothing changed since that build (an AgrOS update's hook, each one running this): no restart, nothing rebuilt
printf '#!/bin/sh\necho "restart $*" >>"%s"\n' "$t/calls" >"$h/.local/bin/caelestia-restart"; rm -f "$t/calls"
touch "$t/running"; inode=$(stat -c %i "$dst")
[[ -e $dst/.agros-built ]] || fail "a build not marked as built: $out"
out=$(run DOTS_SETTINGS=/bin/false nice -n 19) || fail "unchanged: $out"
[[ ! -e $t/calls && $(stat -c %i "$dst") == "$inode" ]] || fail "rebuilt (or restarted) with nothing changed: $out"
# A setting changed (a feature turned off): handed over to be rebuilt
printf '#!/bin/sh\necho "{\\"caelestia.dock\\": false}"\n' >"$t/settings"; chmod +x "$t/settings"
out=$(run DOTS_SETTINGS="$t/settings" nice -n 19) || fail "a setting changed: $out"
[[ $(cat "$t/calls" 2>/dev/null) == "restart --rebuild" ]] || fail "a setting changed: not rebuilt: $out"
# ...with a game open: handed over at once all the same (caelestia-restart waits for the game, merging every request
# during it into one restart: tests/caelestia-restart-rebuild.sh), no waiter of its own restarting it again after
rm -f "$t/calls"; touch "$t/game"
printf '#!/bin/sh\nwhile [ ! -e "%s" ]; do /usr/bin/sleep 0.05; done\nrm -f "%s"\n' "$t/go" "$t/game" >"$sb/sleep"
chmod +x "$sb/sleep"
out=$(run DOTS_SETTINGS="$t/settings" nice -n 19) || fail "a game open: $out"
[[ $(cat "$t/calls" 2>/dev/null) == "restart --rebuild" ]] || fail "a game open: not handed to caelestia-restart --rebuild: $out"
touch "$t/go"; /usr/bin/sleep 1  # (anything a waiter of its own would have done once the game closed)
[[ $(cat "$t/calls") == "restart --rebuild" ]] || fail "a game open: restarted again after it, by a waiter of its own: $(tr '\n' ' ' <"$t/calls")"
echo "ok caelestia-overlay-live"
