#!/usr/bin/env bash
# system/screens-resume (the sleep hook) and .local/bin/screens-on, with systemd-run, hyprctl and sleep stand-ins and
# Hyprland's sockets in a throwaway XDG_RUNTIME_DIR. The hook: after waking only, screens-on for each user in a unit of
# its own, not waited on; before sleep screens-off, waited on. screens-on: a screen off switched on (the Lua dispatcher, in that
# Hyprland), screens on left alone (nothing sent), a Hyprland not answering yet tried again, no Hyprland nothing;
# waking locked, the lock screen's keyboard handed over anew (the pointer to another screen and back)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
printf '#!/bin/sh\necho "systemd-run $*" >>"%s/calls"\n' "$t" >"$t/bin/systemd-run"
printf '#!/bin/sh\n' >"$t/bin/sleep"
# hyprctl -i <sig> monitors: "dpmsStatus: <$t/dpms>" ($t/silent: no answer, that many times); dispatch: noted, the
# screen on
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
echo "hyprctl \$*" >>"$t/calls"
case \$3 in
monitors)
    n=\$(cat "$t/silent" 2>/dev/null || echo 0)
    ((n == 0)) || { echo \$((n - 1)) >"$t/silent"; exit 1; }
    # (-j: two screens, the second turned a quarter, as this machine's)
    [[ \${4:-} == -j ]] && { echo '[{"x":0,"y":280,"width":2560,"height":1440,"scale":1,"transform":0},{"x":2624,"y":0,"width":1920,"height":1080,"scale":1,"transform":3}]'; exit 0; }
    printf 'Monitor DP-1 (ID 0):\n\tdpmsStatus: %s\n' "\$(cat "$t/dpms")" ;;
cursorpos) echo '{"x": 1000.5, "y": 700}' ;;
dispatch) [[ \$4 == *dpms* ]] && echo 1 >"$t/dpms" ;;
esac
STUB
# qs: Caelestia's lock on ($t/locked) or not
printf '#!/bin/sh\n[ -e "%s/locked" ] && echo true || echo false\n' "$t" >"$t/bin/qs"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH

# The hook: before sleep, screens-off for each user, waited on; after waking, screens-on for each user, in a unit of
# its own (--no-block)
printf '#!/bin/sh\necho "each-user $*" >>"%s/calls"\n' "$t" >"$t/bin/each-user"
chmod +x "$t/bin/each-user"
AGROS_EACH_USER=$t/bin/each-user "$here/system/screens-resume" pre || fail "the hook failed before sleep"
[[ $(cat "$t/calls") == "each-user --limit 8 screens-off" ]] || fail "screens-off not run for each user before sleep: $(cat "$t/calls")"
rm -f "$t/calls"
AGROS_EACH_USER=/x/agros-each-user "$here/system/screens-resume" post || fail "the hook failed after waking"
[[ $(cat "$t/calls") == "systemd-run --quiet --collect --no-block /x/agros-each-user screens-on" ]] ||
    fail "screens-on not started for each user in a unit of its own: $(cat "$t/calls")"

on() { rm -f "$t/calls"; timeout 20 "$here/.local/bin/screens-on" || fail "screens-on failed"; }
# No Hyprland: nothing asked
on; [[ ! -e $t/calls ]] || fail "hyprctl asked with no Hyprland: $(cat "$t/calls")"
sig=abc_123
mkdir -p "$XDG_RUNTIME_DIR/hypr/$sig"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$XDG_RUNTIME_DIR/hypr/$sig/.socket.sock"
# A screen off: switched on, in that Hyprland, by the Lua config's dispatcher, once
echo 0 >"$t/dpms"; on
[[ $(grep -c dispatch "$t/calls") == 1 ]] &&
    grep -qxF "hyprctl -i $sig dispatch hl.dsp.dpms({ action = \"enable\" })" "$t/calls" || fail "a screen off not switched on: $(cat "$t/calls")"
# Screens on: nothing sent (a fullscreen game left as it is)
on; ! grep -q dispatch "$t/calls" || fail "screens already on sent dpms: $(cat "$t/calls")"
# Not answering at first (just after waking): asked again, then switched on
echo 0 >"$t/dpms"; echo 2 >"$t/silent"; on
[[ $(grep -c ' monitors' "$t/calls") -ge 3 && $(cat "$t/dpms") == 1 ]] || fail "a Hyprland not answering yet not tried again: $(cat "$t/calls")"
# Waking locked: the pointer to the middle of the other screen (the turned one: 1080 wide as laid out) and straight
# back, the lock screen's keyboard handed over anew; not locked, the pointer left alone
touch "$t/locked"; on
[[ $(grep -o 'cursor.move({[^}]*})' "$t/calls" | paste -sd' ') == "cursor.move({ x = 3164, y = 960 }) cursor.move({ x = 1000, y = 700 })" ]] ||
    fail "the lock screen's keyboard not handed over anew after waking locked: $(cat "$t/calls")"
rm -f "$t/locked"; on
! grep -q cursor.move "$t/calls" || fail "the pointer moved after waking unlocked: $(cat "$t/calls")"
# screens-off: each Hyprland's screens switched off (the Lua dispatcher), then the fade waited for; none, nothing
rm -f "$t/calls"; timeout 20 "$here/.local/bin/screens-off" || fail "screens-off failed"
grep -qxF "hyprctl -i $sig dispatch hl.dsp.dpms({ action = \"disable\" })" "$t/calls" || fail "screens not switched off before sleep: $(cat "$t/calls")"
rm -rf "${XDG_RUNTIME_DIR:?}/hypr"; rm -f "$t/calls"
timeout 20 "$here/.local/bin/screens-off" || fail "screens-off with no Hyprland failed"
[[ ! -e $t/calls ]] || fail "screens-off asked with no Hyprland: $(cat "$t/calls")"
echo "ok screens-resume"
