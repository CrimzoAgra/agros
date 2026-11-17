#!/usr/bin/env bash
# caelestia-restart --rebuild: the overlay rebuilt only once the shell is stopped (rebuilt under it, Hyprland dropped
# the shell), and the shell started again after, even when the rebuild fails
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home/.local/bin" "$t/bin"
# A fake qs: one Caelestia running until it's killed; its starts and kills logged
cat >"$t/bin/qs" <<S
#!/bin/sh
case "\$1" in
    list) [ -e "$t/running" ] && printf 'Process ID: %s\nConfig path: /x/quickshell/caelestia/shell.qml\n' "\$(cat "$t/running")" ;;
    kill) rm -f "$t/running"; echo kill >>"$t/log" ;;
    -c) echo start >>"$t/log"; echo 43 >"$t/running" ;;
esac
S
printf '#!/bin/sh\n[ -e "%s/running" ] && echo "rebuilt while running" >>"%s/log" || echo rebuilt >>"%s/log"\nexit "${FAIL:-0}"\n' "$t" "$t" "$t" >"$t/home/.local/bin/caelestia-overlay"
printf '#!/bin/sh\necho "$*" >>"%s/units"\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' "$t" >"$t/bin/systemd-run"  # (its options skipped; logged)
printf '#!/bin/sh\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/setsid"  # (in the foreground here)
# Spotify running, hidden in the tray: its window rules on before the stop (logged), off again on a failure
printf '#!/bin/sh\nexit 0\n' >"$t/bin/pgrep"
printf '#!/bin/sh\ncase "$1" in clients) echo "[]" ;; eval) echo "$2" >>"%s/hypr" ;; esac\n' "$t" >"$t/bin/hyprctl"
printf '#!/bin/sh\necho notified >>"%s/log"\n' "$t" >"$t/bin/notify-send"
# (beside the stubbed overlay: the scripts it runs are the ones beside itself)
cp "$here/.local/bin/"{caelestia-restart,dots-warn,notify-when-up} "$t/home/.local/bin/"
# (a game open while $t/game is there; after-games: the game closed, logged)
printf '#!/bin/sh\n[ -e "%s/game" ]\n' "$t" >"$t/home/.local/bin/game-focus"
printf '#!/bin/sh\necho after-games >>"%s/log"; rm -f "%s/game"\n' "$t" "$t" >"$t/home/.local/bin/after-games"
chmod +x "$t/bin/"* "$t/home/.local/bin/"*
run() { echo 42 >"$t/running"; : >"$t/log"; : >"$t/hypr"; rc=0; HOME=$t/home HYPRLAND_INSTANCE_SIGNATURE=x WAYLAND_DISPLAY=w XDG_CURRENT_DESKTOP=Hyprland PATH=$t/bin:$PATH "$t/home/.local/bin/caelestia-restart" "$@" >/dev/null 2>&1 || rc=$?; }
run --rebuild
((rc == 0)) || fail "exit $rc after a good rebuild"
[[ $(cat "$t/log") == $'kill\nrebuilt\nstart' ]] || fail "not stopped, rebuilt, started: $(tr '\n' ' ' <"$t/log")"
[[ $(cat "$t/hypr") == 'dots.spotify_silent_set(true)' ]] || fail "Spotify's window rules not just on: $(tr '\n' ' ' <"$t/hypr")"
# A game open: not stopped, rebuilt or started until it closes (after-games: in the background, run here at once), said
touch "$t/game"; run --rebuild
((rc == 0)) || fail "exit $rc with a game open"
[[ $(cat "$t/log") == $'notified\nafter-games\nkill\nrebuilt\nstart' || $(cat "$t/log") == $'after-games\nkill\nrebuilt\nstart\nnotified' ]] ||
    fail "with a game open: not restarted after it, or not said: $(tr '\n' ' ' <"$t/log")"
# Three requests during one game, one a --rebuild: one restart after it (rebuilt), said once. (The waiter in the
# background here, after-games holding while $t/hold is there; the shell's own scope still in the foreground)
cp "$t/bin/systemd-run" "$t/systemd-run.fg"
printf '#!/bin/sh\ncase " $* " in *" --scope "*) exec "%s/systemd-run.fg" "$@" ;; esac\nwhile [ "${1#-}" != "$1" ]; do shift; done\n"$@" >/dev/null 2>&1 &\n' "$t" >"$t/bin/systemd-run"
printf '#!/bin/sh\nwhile [ -e "%s/hold" ]; do sleep 0.1; done\necho after-games >>"%s/log"; rm -f "%s/game"\n' "$t" "$t" "$t" >"$t/home/.local/bin/after-games"
echo 42 >"$t/running"; : >"$t/log"; touch "$t/game" "$t/hold"
for arg in "" --rebuild ""; do
    HOME=$t/home HYPRLAND_INSTANCE_SIGNATURE=x WAYLAND_DISPLAY=w XDG_CURRENT_DESKTOP=Hyprland PATH=$t/bin:$PATH "$t/home/.local/bin/caelestia-restart" $arg >/dev/null 2>&1 ||
        fail "a request during a game ($arg) failed"
done
rm "$t/hold"
for _ in $(seq 100); do grep -q '^start$' "$t/log" && break; sleep 0.1; done
sleep 0.3  # (anything a second waiter would have done)
[[ $(sort "$t/log" | tr '\n' ' ') == "after-games kill notified rebuilt start " ]] ||
    fail "three requests during a game not one restart (rebuilt), said once: $(tr '\n' ' ' <"$t/log")"
[[ -e $XDG_RUNTIME_DIR/caelestia-restart-pending ]] && fail "the pending restart left behind after it ran"
cp "$t/systemd-run.fg" "$t/bin/systemd-run"
printf '#!/bin/sh\necho after-games >>"%s/log"; rm -f "%s/game"\n' "$t" "$t" >"$t/home/.local/bin/after-games"
FAIL=1 run --rebuild
grep -q '^start$' "$t/log" || fail "a failed rebuild left no shell"
# Its skipped changes said once the new shell is up (Caelestia is the notification server: said before, nobody got it)
mkdir -p "$t/home/.local/state"; echo "The overlay failed, Caelestia runs without your changes: x" >"$t/home/.local/state/caelestia-overlay-skipped"
FAIL=1 run --rebuild
[[ $(tail -2 "$t/log" | tr '\n' ' ') == "start notified " ]] || fail "skipped changes not said after the shell's start: $(tr '\n' ' ' <"$t/log")"
# ...in a scope of its own: after a game, run by the waiter as its unit's main process, whose end kills the unit's
# cgroup (a setsid'd warning in it too)
grep -qE -- '--scope .*/dots-warn ' "$t/units" || fail "the skipped changes' warning not in a unit of its own: $(cat "$t/units")"
rm "$t/home/.local/state/caelestia-overlay-skipped"
((rc == 3)) || fail "a failed rebuild exited $rc, not 3 (built, failed, shell started again): the Settings app can't say it failed, caelestia-overlay would build again under the shell"
run
grep -q rebuilt "$t/log" && fail "rebuilt without --rebuild"
# A shell that never comes up: 3, a failure (no waiting the 30 s here: sleep does nothing)
cp "$t/bin/qs" "$t/qs"; sed -i '/^    -c)/s/; echo 43 >"[^"]*"//' "$t/bin/qs"; printf '#!/bin/sh\n' >"$t/bin/sleep"; chmod +x "$t/bin/sleep"
run
((rc == 3)) || fail "a shell that never came up exited $rc, not 3"
unsilenced='dots.spotify_silent_set(true) dots.spotify_silent_set(false) '
[[ $(tr '\n' ' ' <"$t/hypr") == "$unsilenced" ]] || fail "Spotify's window rules left on, no shell up: $(tr '\n' ' ' <"$t/hypr")"
mv "$t/qs" "$t/bin/qs"; rm "$t/bin/sleep"
# A shell that won't close (qs kill does nothing): killed outright (a throwaway sleep standing in for it), then rebuilt
# (disowned: its kill -9 not reported as "Killed")
sleep 60 & stuck=$!; disown
cat >"$t/bin/qs" <<S
#!/bin/sh
case "\$1" in
    list) kill -0 $stuck 2>/dev/null && printf 'Process ID: $stuck\nConfig path: /x/quickshell/caelestia/shell.qml\n'
          [ -e "$t/started" ] && printf 'Process ID: 43\nConfig path: /x/quickshell/caelestia/shell.qml\n' ;;
    kill) echo "polite kill" >>"$t/log" ;;
    -c) echo start >>"$t/log"; touch "$t/started" ;;
esac
S
run --rebuild
kill -0 "$stuck" 2>/dev/null && { kill "$stuck"; fail "a shell that wouldn't close wasn't killed"; }
grep -q '^rebuilt' "$t/log" || fail "not rebuilt once the stuck shell was killed: $(tr '\n' ' ' <"$t/log")"
# One that even kill -9 doesn't take (still listed, as a stuck old shell): no second one started beside it, no rebuild,
# 3, with and without --rebuild; and a lingering old one isn't taken for the new one up
# (a PID above pid_max, that can't exist: the killed sleep's could be reused by then, and the real kill -9 hit it)
nopid=$(($(cat /proc/sys/kernel/pid_max) + 1))
sed -i "s/^    list) kill -0 $stuck 2>\/dev\/null \&\& /    list) /; s/Process ID: $stuck/Process ID: $nopid/" "$t/bin/qs"; printf '#!/bin/sh\n' >"$t/bin/sleep"; chmod +x "$t/bin/sleep"
for arg in --rebuild ""; do
    rm -f "$t/started"; run ${arg:+"$arg"}
    ((rc == 3)) || fail "a shell that wouldn't stop ($arg) exited $rc, not 3"
    [[ $(tr '\n' ' ' <"$t/hypr") == "$unsilenced" ]] || fail "Spotify's window rules left on, the shell not restarted ($arg): $(tr '\n' ' ' <"$t/hypr")"
    grep -qE '^(start|rebuilt)' "$t/log" && fail "started or rebuilt beside a shell that wouldn't stop ($arg): $(tr '\n' ' ' <"$t/log")"
done
# A shell that comes up but never loads its config (qs ipc unanswered: Quickshell left running with nothing on screen),
# on the overlay's changes (a file of its own there): stopped, started again on Caelestia as it comes (caelestia-overlay
# --without-changes), said once it's up, 3. Here it loads whenever $t/noload isn't there and the changes are gone; each
# start a new process ID. (No waiting the 30 s: sleep does nothing)
cat >"$t/bin/qs" <<S
#!/bin/sh
case "\$1" in
    list) [ -e "$t/running" ] && printf 'Process ID: %s\nConfig path: /x/quickshell/caelestia/shell.qml\n' "\$(cat "$t/running")" ;;
    kill) rm -f "$t/running"; echo kill >>"$t/log" ;;
    -c) echo start >>"$t/log"; n=\$(cat "$t/n" 2>/dev/null || echo 43); echo \$((n + 1)) >"$t/n"; echo "\$n" >"$t/running" ;;
    ipc) [ ! -e "$t/noload" ] && [ ! -e "$t/home/.config/quickshell/caelestia/mine.qml" ] ;;
esac
S
cat >"$t/home/.local/bin/caelestia-overlay" <<S
#!/bin/sh
[ "\$1" = --without-changes ] || exit 0
echo "without changes" >>"$t/log"; rm -f "$t/home/.config/quickshell/caelestia/mine.qml"; echo "\$2" >"$t/home/.local/state/caelestia-overlay-skipped"
S
mkdir -p "$t/home/.config/quickshell/caelestia"; touch "$t/home/.config/quickshell/caelestia/mine.qml"
run
((rc == 3)) && [[ $(tr '\n' ' ' <"$t/log") == "kill start kill without changes start notified " ]] ||
    fail "a shell whose config never loaded on the changes not started again without them, said (exit $rc): $(tr '\n' ' ' <"$t/log")"
grep -q "didn't load with your changes" "$t/home/.local/state/caelestia-overlay-skipped" || fail "why the changes are off not written down"
# ...one on Caelestia as it comes already: nothing more to try, 3
rm "$t/home/.local/state/caelestia-overlay-skipped"; touch "$t/noload"
run
((rc == 3)) && [[ $(tr '\n' ' ' <"$t/log") == "kill start " ]] || fail "a shell without the changes whose config never loaded (exit $rc): $(tr '\n' ' ' <"$t/log")"
# ...and --without-changes (caelestia-start's, its shell at login never loaded): stopped, without them, started, said
rm "$t/noload"; touch "$t/home/.config/quickshell/caelestia/mine.qml"
run --without-changes
((rc == 3)) && [[ $(tr '\n' ' ' <"$t/log") == "kill without changes start notified " ]] ||
    fail "--without-changes: not stopped, started without the changes, said (exit $rc): $(tr '\n' ' ' <"$t/log")"
rm "$t/bin/sleep"
echo "ok caelestia-restart-rebuild"
