#!/usr/bin/env bash
# system/bluetooth-resume (the sleep hook), with bluetoothctl, systemctl, rfkill and logger stand-ins and its mark in a
# throwaway folder. Before sleep: Bluetooth's service not running, nothing asked (bluetoothctl would wait for bluetoothd
# forever); bluetoothd stuck, given up on within seconds, not the hook's whole time limit; on: noted. After waking:
# switched back on when it was on, nothing done when it wasn't
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
sed "s|/run/bluetooth-was-powered|$t/was-powered|g" "$here/system/bluetooth-resume" >"$t/hook"
grep -q "$t/was-powered" "$t/hook" || fail "the mark's path not found in bluetooth-resume"
# bluetoothctl: hangs with $BT_HANG (bluetoothd stuck), else answers Powered: $BT_POWERED (yes once switched on with
# $BT_COMES_ON), a device connected with $BT_CONNECTED; systemctl is-active: $BT_ACTIVE
cat >"$t/bin/bluetoothctl" <<STUB
#!/bin/sh
echo "bluetoothctl \$*" >>"$t/calls"
[ -z "\$BT_HANG" ] || exec sleep 60
[ "\$1 \$2" != "power on" ] || [ -z "\$BT_COMES_ON" ] || touch "$t/on"
[ "\$1 \$2" != "devices Connected" ] || [ -z "\$BT_CONNECTED" ] || echo "Device AA:BB:CC:DD:EE:FF Headphones"
[ "\$1" != show ] || { [ -e "$t/on" ] && echo "	Powered: yes" || echo "	Powered: \${BT_POWERED:-no}"; }
STUB
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\n[ -n "$BT_ACTIVE" ]\n' >"$t/bin/systemctl"
printf '#!/bin/sh\necho "logger $*" >>"%s/calls"\n' "$t" >"$t/bin/logger"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/rfkill"
chmod +x "$t/bin/"* "$t/hook"
# The kernel's adapters: a folder of their entries ($t/sys/hci0)
mkdir -p "$t/sys/hci0"
hook() { rm -f "$t/calls"; BT_SYSFS=$t/sys PATH=$t/bin:$PATH timeout 30 "$t/hook" "$@" >/dev/null 2>&1; }

# Bluetooth's service stopped: nothing asked, nothing noted (an old mark taken out)
touch "$t/was-powered"
hook pre || fail "pre failed with the service stopped"
[[ ! -e $t/calls ]] || fail "bluetoothctl asked with the service stopped: $(cat "$t/calls")"
[[ ! -e $t/was-powered ]] || fail "an old mark left with the service stopped"
# bluetoothd stuck: given up on in a few seconds
start=$SECONDS
BT_ACTIVE=1 BT_HANG=1 hook pre || fail "pre failed with bluetoothd stuck"
((SECONDS - start <= 6)) || fail "pre waited $((SECONDS - start)) s on a stuck bluetoothd"
[[ ! -e $t/was-powered ]] || fail "noted as on with bluetoothd stuck"
# On: noted, and switched back on after waking
BT_ACTIVE=1 BT_POWERED=yes hook pre || fail "pre failed"
[[ -e $t/was-powered ]] || fail "Bluetooth on before sleep not noted"
# (the adapter reset on waking, back off: switched on, then off and on once for Caelestia's bar)
BT_ACTIVE=1 BT_COMES_ON=1 hook post || fail "post failed"
[[ $(grep -c "^bluetoothctl power on" "$t/calls") == 2 && $(grep -c "^bluetoothctl power off" "$t/calls") == 1 ]] ||
    fail "not switched back on after waking: $(cat "$t/calls")"
grep -q "^logger.*back on" "$t/calls" || fail "switching back on not logged: $(cat "$t/calls")"
[[ ! -e $t/was-powered ]] || fail "the mark left after waking"
rm -f "$t/on"
# Its links kept through the sleep (the same adapter as before, on, a device still connected): left alone, not
# switched off and on
BT_ACTIVE=1 BT_POWERED=yes hook pre
BT_ACTIVE=1 BT_POWERED=yes BT_CONNECTED=1 hook post || fail "post failed with Bluetooth still on"
{ ! grep -q "^bluetoothctl power" "$t/calls" && grep -q "^logger.*kept its connections" "$t/calls"; } ||
    fail "an adapter that kept its links through sleep switched off and on: $(cat "$t/calls")"
# The adapter reset (made anew: a new entry under the same name), already on (BlueZ's AutoEnable), bluetoothd still
# listing a device from before: switched off and on as after any reset, for the bar
BT_ACTIVE=1 BT_POWERED=yes hook pre
mkdir "$t/sys/hci0.new"; rmdir "$t/sys/hci0"; mv "$t/sys/hci0.new" "$t/sys/hci0"
BT_ACTIVE=1 BT_POWERED=yes BT_CONNECTED=1 hook post || fail "post failed after a reset"
[[ $(grep -c "^bluetoothctl power off" "$t/calls") == 1 ]] || fail "a reset adapter (on, by AutoEnable) not switched off and on: $(cat "$t/calls")"
# The same adapter on, nothing connected (no links to keep, or a reset still under way): switched off and on too
BT_ACTIVE=1 BT_POWERED=yes hook pre
BT_ACTIVE=1 BT_POWERED=yes hook post || fail "post failed with nothing connected"
[[ $(grep -c "^bluetoothctl power off" "$t/calls") == 1 ]] || fail "an adapter on with nothing connected not switched off and on: $(cat "$t/calls")"
# Not answering after waking (bluetoothd stuck): still given up on within the time limit
BT_ACTIVE=1 BT_POWERED=yes hook pre
start=$SECONDS
BT_ACTIVE=1 BT_HANG=1 hook post || fail "post failed with bluetoothd stuck"
((SECONDS - start <= 22)) || fail "post waited $((SECONDS - start)) s on a stuck bluetoothd"
# Off before sleep: nothing done after waking
BT_ACTIVE=1 BT_POWERED=no hook pre
[[ ! -e $t/was-powered ]] || fail "Bluetooth off noted as on"
BT_ACTIVE=1 hook post || fail "post failed with Bluetooth off"
[[ ! -e $t/calls ]] || fail "something done after waking with Bluetooth off before: $(cat "$t/calls")"
echo "ok bluetooth-resume"
