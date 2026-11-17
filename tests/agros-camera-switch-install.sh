#!/usr/bin/env bash
# agros-camera-switch's install script (packages/agros-camera-switch/agros-camera-switch.install) in a throwaway root
# (AGROS_ROOT), its tools stand-ins: the install makes the switch's saved position and starts the daemon now, not only
# from the next boot (agros-welcome --system installs it on a running desktop: the switch did nothing until a restart);
# an upgrade has a running one restarted after the transaction (marked, not restarted from here); removal stops it,
# removes the saved position and puts the camera back where the switch had taken it out
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/root
export AGROS_ROOT=$r
mkdir -p "$t/bin" "$r/var/lib/camera-switch"
# shellcheck disable=SC2016  # (expanded by the stand-in: $ACTIVE, the daemon running)
printf '#!/bin/sh\necho "systemctl $*" >>%s/calls\ncase "$*" in *is-active*) [ -n "$ACTIVE" ] ;; esac\n' "$t" >"$t/bin/systemctl"
printf '#!/bin/sh\necho "systemd-tmpfiles $*" >>%s/calls\n' "$t" >"$t/bin/systemd-tmpfiles"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
# shellcheck source=../packages/agros-camera-switch/agros-camera-switch.install
. "$here/packages/agros-camera-switch/agros-camera-switch.install"
pac() { (set +e; "$@"); }
calls() { cat "$t/calls" 2>/dev/null; }

pac post_install
[[ $(calls) == "$(printf '%s\n' 'systemd-tmpfiles --create /usr/lib/tmpfiles.d/agros-camera-switch.conf' \
    'systemctl enable --now camera-switch.service')" ]] ||
    fail "the install didn't make the saved position, then start the daemon now: $(calls)"
# Upgrade: a running one marked for its restart after the transaction; one not running left alone
rm -f "$t/calls"; ACTIVE=1 pac post_upgrade
grep -qx 'systemctl set-property camera-switch.service Markers=+needs-restart' <<<"$(calls)" || fail "running: not marked: $(calls)"
! grep -q 'restart\b' <<<"$(calls | grep -v needs-restart)" || fail "restarted from the scriptlet: $(calls)"
rm -f "$t/calls"; pac post_upgrade
! grep -q set-property <<<"$(calls)" || fail "not running, yet marked: $(calls)"
# Removal: stopped, the saved position gone, the camera (taken out by the switch) authorised again, another device not
rm -f "$t/calls"
for d in 1-5 1-6; do mkdir -p "$r/sys/bus/usb/devices/$d"; echo 0 >"$r/sys/bus/usb/devices/$d/authorized"; done
printf '04f2\n' >"$r/sys/bus/usb/devices/1-5/idVendor"; printf 'b83e\n' >"$r/sys/bus/usb/devices/1-5/idProduct"
printf '046d\n' >"$r/sys/bus/usb/devices/1-6/idVendor"; printf 'c08b\n' >"$r/sys/bus/usb/devices/1-6/idProduct"
echo off >"$r/var/lib/camera-switch/state"
pac pre_remove; pac post_remove
grep -qx 'systemctl disable --now camera-switch.service' <<<"$(calls)" || fail "not stopped at removal: $(calls)"
[[ ! -e $r/var/lib/camera-switch ]] || fail "the saved position left"
[[ $(cat "$r/sys/bus/usb/devices/1-5/authorized") == 1 && $(cat "$r/sys/bus/usb/devices/1-6/authorized") == 0 ]] ||
    fail "the camera not put back (or another device touched)"
echo "ok agros-camera-switch-install"
