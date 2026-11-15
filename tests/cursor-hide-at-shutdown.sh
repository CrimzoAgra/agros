#!/usr/bin/env bash
# cursor-hide-at-shutdown: under logind's delay lock, the pointer hidden at PrepareForShutdown(true) (not at a sleep's
# PrepareForSleep) and then the lock let go, letting the shutdown go on; a shutdown called off after that (false) brings
# the pointer back and the lock is taken again, by the same listener (none started anew, to miss the signal)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export log=$t/calls
mkdir -p "$t/bin"
printf '#!/bin/sh\necho "inhibit $*" >>"$log"\nshift 4; "$@"; echo released >>"$log"\n' >"$t/bin/systemd-inhibit"
# (a sleep, a "called off" with no shutdown before it, a shutdown (its signal twice), called off, and another, each with
# systemd 255's WithMetadata signal beside it; then the stream ends, and the helper with it. Neither the stray "called
# off" nor the second signal does anything)
cat >"$t/bin/gdbus" <<'G'
#!/bin/sh
echo "gdbus" >>"$log"
sleep 0.3
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (false,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdownWithMetadata (true, {'type': <'poweroff'>})"
# (called off once the shutdown went on, the lock let go: as logind's own, seconds later)
for _ in $(seq 50); do grep -q '^released' "$log" && break; sleep 0.1; done
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (false,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdownWithMetadata (false, @a{sv} {})"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)"
echo "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdownWithMetadata (true, {'type': <'poweroff'>})"
sleep 0.3
G
printf '#!/bin/sh\necho "hyprctl $*" >>"$log"\n' >"$t/bin/hyprctl"
chmod +x "$t/bin/"*
# (its Hyprland, as its lock file names it: running, the session going on)
export XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test CURSOR_HIDE_POLL=0.2
mkdir -p "$t/run/hypr/test"
sleep 60 &
hypr=$!
on_exit 'kill "$hypr" 2>/dev/null'
printf '%s\nwayland-1\n' "$hypr" >"$t/run/hypr/test/hyprland.lock"
PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/cursor-hide-at-shutdown" || fail "it didn't end with the signals"
for _ in $(seq 50); do [[ $(grep -c '^released' "$log") == 2 ]] && break; sleep 0.1; done
# (the listener and the first lock start side by side: their order not the script's to keep)
seq=$(grep -vx gdbus "$log" | sed -E 's/^inhibit --what=shutdown --mode=delay .*/inhibit/; s/^hyprctl .*invisible = (true|false).*/\1/')
[[ $(grep -cx gdbus "$log") == 1 && $seq == $'inhibit\ntrue\nreleased\nfalse\ninhibit\ntrue\nreleased' ]] ||
    fail "not: one listener, the lock held, the pointer hidden before the lock let go, back and the lock again when called off: $(cat "$log")"
# The lock refused (systemd-inhibit failing): the pointer hidden all the same, and nothing to let go (no error)
printf '#!/bin/sh\necho "inhibit refused" >>"$log"\nexit 1\n' >"$t/bin/systemd-inhibit"
: >"$log"
err=$(PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/cursor-hide-at-shutdown" 2>&1 >/dev/null) || fail "it didn't end, the lock refused"
{ [[ -z $err ]] && grep -q 'invisible = true' "$log"; } || fail "the lock refused: the pointer not hidden, or an error: $err / $(cat "$log")"
# Its Hyprland gone (logged out, or crashed: its socket left behind; logind keeps a user's processes by default):
# ended, its listener with it, no signal needed
printf '#!/bin/sh\necho gdbus >>"$log"\nexec sleep 37.3\n' >"$t/bin/gdbus"
printf '#!/bin/sh\necho "inhibit" >>"$log"; shift 4; exec "$@"\n' >"$t/bin/systemd-inhibit"
: >"$log"
python3 -Ic 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$t/run/hypr/test/.socket.sock"
kill "$hypr"; wait "$hypr" 2>/dev/null || true
PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/cursor-hide-at-shutdown" || fail "it didn't end with its Hyprland"
sleep 0.2
grep -qx "sleep 37.3" <<<"$(ps -eo args=)" && fail "its listener left running"
echo "ok cursor-hide-at-shutdown"
