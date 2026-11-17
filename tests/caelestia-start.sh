#!/usr/bin/env bash
# caelestia-start: runs the overlay's build at every login (it rebuilds only what's out of date), sets the wallpaper and colours the first time (before the
# shell), starts the shell either way (even after a failed build), and logs them
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home/.local/bin" "$t/bin"
# (beside it: the helpers it runs are the ones beside itself)
cp "$here/.local/bin/caelestia-start" "$here/.local/bin/qs-running" "$t/home/.local/bin/"
cat >"$t/home/.local/bin/caelestia-overlay" <<'S'
#!/usr/bin/env bash
echo built >>"$HOME/overlay-runs"
[[ -n ${CAELESTIA_REBUILDING:-} ]] || exit 9  # (its caller holds the lock: taken again, it would wait for good)
mkdir -p "$HOME/.config/quickshell/caelestia" && touch "$HOME/.config/quickshell/caelestia/shell.qml"
exit "${FAIL:-0}"
S
printf '#!/usr/bin/env bash\necho "caelestia $*" >>"$HOME/started"\n' >"$t/bin/caelestia"
# (the shell up at once: not the live one looked for, nor 30 s waited where there's none, CI)
printf '#!/bin/sh\necho "Config path: /x/quickshell/caelestia/shell.qml"\n' >"$t/bin/qs"
printf '#!/bin/sh\necho greeter-theme-sync >>"$HOME/started"\n' >"$t/home/.local/bin/greeter-theme-sync"
chmod +x "$t/home/.local/bin/caelestia-overlay" "$t/bin/caelestia" "$t/bin/qs" "$t/home/.local/bin/greeter-theme-sync"
run() { HOME=$t/home PATH=$t/bin:$PATH "$t/home/.local/bin/caelestia-start"; }
log=$t/home/.local/state/agros/caelestia-start.log

run
[[ $(cat "$t/home/overlay-runs") == built ]] || fail "first login: the overlay wasn't built"
[[ $(tail -1 "$t/home/started") == "caelestia shell -d" ]] || fail "first login: the shell wasn't started last"
grep -q '^caelestia scheme set -n dynamic$' "$t/home/started" || fail "first login: the colours weren't set"
[[ -e $t/home/.local/state/agros/wallpaper-set ]] || fail "first login: the wallpaper's mark isn't there"
# (the login screen's copy of them once they're set: at Hyprland's start, before, they weren't there yet)
[[ $(grep -A1 '^caelestia scheme set' "$t/home/started" | tail -1) == greeter-theme-sync ]] ||
    fail "first login: the login screen not given the wallpaper and colours once set: $(cat "$t/home/started")"
grep -q 'overlay checked: exit 0' "$log" || fail "first login: the build isn't logged"

# (with the overlay there too: a rebuild left waiting for a game, lost with the session, made at the next login)
run
[[ $(wc -l <"$t/home/overlay-runs") -eq 2 ]] || fail "next login: the overlay wasn't checked"
[[ $(grep -c 'shell -d' "$t/home/started") -eq 2 ]] || fail "next login: the shell wasn't started"
[[ $(grep -c '^caelestia wallpaper' "$t/home/started") -eq 1 ]] || fail "next login: the wallpaper was set again"
[[ $(grep -c '^greeter-theme-sync' "$t/home/started") -eq 1 ]] || fail "next login: the login screen's copy made again"

rm -rf "$t/home/.config/quickshell/caelestia"
FAIL=1 run
[[ $(grep -c 'shell -d' "$t/home/started") -eq 3 ]] || fail "a failed build: the shell wasn't started anyway"
grep -q 'overlay checked: exit 1' "$log" || fail "a failed build: its exit code isn't logged"

# An install from before the mark, with a wallpaper picked since (Caelestia's path.txt): not replaced
rm "$t/home/.local/state/agros/wallpaper-set"; : >"$t/home/started"
mkdir -p "$t/home/.local/state/caelestia/wallpaper"; echo /pics/mine.jpg >"$t/home/.local/state/caelestia/wallpaper/path.txt"
run
grep -q '^caelestia wallpaper' "$t/home/started" && fail "an existing install: its wallpaper replaced"
[[ -e $t/home/.local/state/agros/wallpaper-set ]] || fail "an existing install: no mark"

# Up but its config never loaded (qs ipc unanswered: Quickshell running with nothing on screen, no bar, no
# notifications), on the overlay's changes (its shell.qml a file of its own here): handed to caelestia-restart
# --without-changes. On Caelestia as it comes (links only): nothing more to try. (No waiting the 30 s: sleep does nothing)
printf '#!/bin/sh\n[ "$1" = ipc ] && exit 255\necho "Config path: /x/quickshell/caelestia/shell.qml"\n' >"$t/bin/qs"
printf '#!/bin/sh\n' >"$t/bin/sleep"
printf '#!/bin/sh\necho "restart $*" >>"$HOME/started"\n' >"$t/home/.local/bin/caelestia-restart"
chmod +x "$t/bin/qs" "$t/bin/sleep" "$t/home/.local/bin/caelestia-restart"
: >"$t/home/started"
run
[[ $(tail -1 "$t/home/started") == "restart --without-changes" ]] ||
    fail "a shell whose config never loaded not started again without the changes: $(cat "$t/home/started")"
grep -q "didn't load with AgrOS's changes" "$log" || fail "a shell whose config never loaded: not logged"
sed -i 's|touch "\$HOME/.config/quickshell/caelestia/shell.qml"|ln -sf /x "$HOME/.config/quickshell/caelestia/shell.qml"|' "$t/home/.local/bin/caelestia-overlay"
rm -rf "$t/home/.config/quickshell/caelestia"; : >"$t/home/started"
run
grep -q '^restart' "$t/home/started" && fail "a shell on Caelestia as it comes restarted again: $(cat "$t/home/started")"
# --prepare (caelestia-prepare.service, as the session starts): the build and the first wallpaper and colours done,
# the shell not started; the run at Hyprland's start then finds them done and only starts the shell
# (no shell running yet: qs lists none)
printf '#!/bin/sh
exit 0
' >"$t/bin/qs"
cp "$here/.local/bin/caelestia-start" "$t/home/.local/bin/"
rm -rf "$t/home/.local/state" "$t/home/.config/quickshell/caelestia" "$t/home/overlay-runs"; : >"$t/home/started"
HOME=$t/home PATH=$t/bin:$PATH "$t/home/.local/bin/caelestia-start" --prepare
[[ $(cat "$t/home/overlay-runs") == built ]] || fail "--prepare: the overlay wasn't built"
grep -q '^caelestia scheme set -n dynamic$' "$t/home/started" || fail "--prepare: the colours weren't set"
grep -q 'shell -d' "$t/home/started" && fail "--prepare: the shell was started: $(cat "$t/home/started")"
grep -q '(ahead of the desktop)' "$log" || fail "--prepare: not logged as such"
printf '#!/bin/sh
echo "Config path: /x/quickshell/caelestia/shell.qml"
' >"$t/bin/qs"
run
[[ $(grep -c '^caelestia wallpaper' "$t/home/started") -eq 1 ]] || fail "after --prepare: the wallpaper was set again"
# (a shell already up from that folder: --prepare builds nothing under it)
HOME=$t/home PATH=$t/bin:$PATH "$t/home/.local/bin/caelestia-start" --prepare
[[ $(wc -l <"$t/home/overlay-runs") -eq 2 ]] || fail "--prepare with the shell up: built under it"
[[ $(tail -1 "$t/home/started") == "caelestia shell -d" ]] || fail "after --prepare: the shell wasn't started"
# (the unit that runs it: packaged, wanted as the session starts, after agros-links and uwsm's environment loader.
# Hyprland waits for it (graphical-session-pre.target is after what it wants, and uwsm starts Hyprland after that), so
# a time limit: a oneshot has none, and one that hung kept the screen black after the login for good)
u=$here/packages/agros-scripts/caelestia-prepare.service
grep -qx 'ExecStart=/usr/lib/agros/bin/caelestia-start --prepare' "$u" &&
    grep -qx 'After=agros-links.service wayland-wm-env@hyprland.desktop.service' "$u" &&
    grep -qx 'WantedBy=graphical-session-pre.target' "$u" && ! grep -q '^Before=' "$u" || fail "caelestia-prepare.service: $(cat "$u")"
limit=$(sed -n 's/^TimeoutStartSec=//p' "$u")
[[ $limit =~ ^[0-9]+$ ]] && ((limit > 0 && limit <= 120)) || fail "caelestia-prepare.service: Hyprland waits on it with no time limit (TimeoutStartSec)"
grep -q 'graphical-session-pre.target.wants/caelestia-prepare.service' "$here/packages/agros-scripts/PKGBUILD" ||
    fail "agros-scripts doesn't enable caelestia-prepare.service"
echo "ok caelestia-start"
