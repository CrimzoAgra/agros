#!/usr/bin/env bash
# system/screens-resume (the sleep hook) and .local/bin/screens-on, with systemd-run, hyprctl and sleep stand-ins and
# Hyprland's sockets in a throwaway XDG_RUNTIME_DIR. The hook: after waking only, screens-on for each user in a unit of
# its own, not waited on; before sleep nothing. screens-on: a screen off switched on (the Lua dispatcher, in that
# Hyprland), screens on left alone (nothing sent), a Hyprland not answering yet tried again, no Hyprland nothing
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
    printf 'Monitor DP-1 (ID 0):\n\tdpmsStatus: %s\n' "\$(cat "$t/dpms")" ;;
dispatch) echo 1 >"$t/dpms" ;;
esac
STUB
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH

# The hook: before sleep nothing; after waking, screens-on for each user, in a unit of its own (--no-block)
"$here/system/screens-resume" pre
[[ ! -e $t/calls ]] || fail "something run before sleep: $(cat "$t/calls")"
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
echo "ok screens-resume"
