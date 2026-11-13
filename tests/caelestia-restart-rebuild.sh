#!/usr/bin/env bash
# caelestia-restart --rebuild: the overlay rebuilt only once the shell is stopped (rebuilt under it, Hyprland dropped
# the shell), and the shell started again after, even when the rebuild fails
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home/.local/bin" "$t/bin"
# A fake qs: one Caelestia running until it's killed; its starts and kills logged
cat >"$t/bin/qs" <<S
#!/bin/sh
case "\$1" in
    list) [ -e "$t/running" ] && printf 'Process ID: 42\nConfig path: /x/quickshell/caelestia/shell.qml\n' ;;
    kill) rm -f "$t/running"; echo kill >>"$t/log" ;;
    -c) echo start >>"$t/log"; touch "$t/running" ;;
esac
S
printf '#!/bin/sh\n[ -e "%s/running" ] && echo "rebuilt while running" >>"%s/log" || echo rebuilt >>"%s/log"\nexit "${FAIL:-0}"\n' "$t" "$t" "$t" >"$t/home/.local/bin/caelestia-overlay"
printf '#!/bin/sh\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/systemd-run"  # (its options skipped)
printf '#!/bin/sh\nexec "$@"\n' >"$t/bin/setsid"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/hyprctl"
printf '#!/bin/sh\necho notified >>"%s/log"\n' "$t" >"$t/bin/notify-send"
chmod +x "$t/bin/"* "$t/home/.local/bin/"*
run() { touch "$t/running"; : >"$t/log"; rc=0; HOME=$t/home HYPRLAND_INSTANCE_SIGNATURE=x WAYLAND_DISPLAY=w PATH=$t/bin:$PATH "$here/.local/bin/caelestia-restart" "$@" >/dev/null 2>&1 || rc=$?; }
run --rebuild
((rc == 0)) || fail "exit $rc after a good rebuild"
[[ $(cat "$t/log") == $'kill\nrebuilt\nstart' ]] || fail "not stopped, rebuilt, started: $(tr '\n' ' ' <"$t/log")"
FAIL=1 run --rebuild
grep -q '^start$' "$t/log" || fail "a failed rebuild left no shell"
# Its skipped changes said once the new shell is up (Caelestia is the notification server: said before, nobody got it)
mkdir -p "$t/home/.local/state"; echo "The overlay failed, Caelestia runs without your changes: x" >"$t/home/.local/state/caelestia-overlay-skipped"
FAIL=1 run --rebuild
[[ $(tail -2 "$t/log" | tr '\n' ' ') == "start notified " ]] || fail "skipped changes not said after the shell's start: $(tr '\n' ' ' <"$t/log")"
rm "$t/home/.local/state/caelestia-overlay-skipped"
((rc == 3)) || fail "a failed rebuild exited $rc, not 3 (built, failed, shell started again): the Settings app can't say it failed, caelestia-overlay would build again under the shell"
run
grep -q rebuilt "$t/log" && fail "rebuilt without --rebuild"
# A shell that won't close (qs kill does nothing): killed outright (a throwaway sleep standing in for it), then rebuilt
sleep 60 & stuck=$!
cat >"$t/bin/qs" <<S
#!/bin/sh
case "\$1" in
    list) { kill -0 $stuck 2>/dev/null || [ -e "$t/started" ]; } && printf 'Process ID: $stuck\nConfig path: /x/quickshell/caelestia/shell.qml\n' ;;
    kill) echo "polite kill" >>"$t/log" ;;
    -c) echo start >>"$t/log"; touch "$t/started" ;;
esac
S
run --rebuild
kill -0 "$stuck" 2>/dev/null && { kill "$stuck"; fail "a shell that wouldn't close wasn't killed"; }
grep -q '^rebuilt' "$t/log" || fail "not rebuilt once the stuck shell was killed: $(tr '\n' ' ' <"$t/log")"
echo "ok caelestia-restart-rebuild"
