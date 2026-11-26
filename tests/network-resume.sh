#!/usr/bin/env bash
# network-resume (agros-system's sleep hook): after waking, a timer of its own runs it again later ("wake"), which
# wakes NetworkManager only while it's still asleep (logind's "resumed" signal lost); nothing before sleep
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
hook=$here/system/network-resume
# (busctl: NetworkManager's state, $STATE; its Sleep call noted. systemd-run and logger noted)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\ncase "$1" in get-property) echo "u $STATE" ;; call) echo "busctl $*" >>%s/calls ;; esac\n' "$t" >"$t/bin/busctl"
for c in systemd-run logger; do printf '#!/bin/sh\necho "%s $*" >>%s/calls\n' "$c" "$t" >"$t/bin/$c"; done
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
: >"$t/calls"
"$hook" pre suspend
[[ ! -s $t/calls ]] || fail "something done before sleep: $(cat "$t/calls")"
"$hook" post suspend
grep -qx "systemd-run --quiet --collect --on-active=20 --unit=agros-network-resume $hook wake" "$t/calls" ||
    fail "no timer of its own started after waking: $(cat "$t/calls")"
: >"$t/calls"
STATE=10 "$hook" wake
grep -qx 'busctl call org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Sleep b false' "$t/calls" &&
    grep -q '^logger -t network-resume ' "$t/calls" || fail "NetworkManager still asleep not woken, or not said: $(cat "$t/calls")"
for s in 70 20; do
    : >"$t/calls"
    STATE=$s "$hook" wake
    [[ ! -s $t/calls ]] || fail "NetworkManager in state $s woken: $(cat "$t/calls")"
done
echo "ok network-resume"
