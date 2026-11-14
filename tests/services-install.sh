#!/usr/bin/env bash
# agros-system's and agros-camera-switch's install scripts (packages/*/*.install) in a throwaway root (AGROS_ROOT), a
# systemctl stand-in: the services on at install, passwd's PAM given the keyring's line once and back at removal; at
# upgrade the wired-link watch on only where it never ran (no /var/lib/agros/wired-link), and a running service marked
# for systemd's restart, a stopped one not; the switch's saved position gone at removal, the camera put back
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/root
export AGROS_ROOT=$r
mkdir -p "$r/etc/pam.d" "$r/var/lib/camera-switch" "$t/bin"
# (is-active: as $t/active says)
printf '#!/bin/sh\necho "systemctl $*" >>%s/calls\n[ "$2" = is-active ] && [ -e %s/active ] && exit 0\n[ "$2" != is-active ]\n' \
    "$t" "$t" >"$t/bin/systemctl"
printf '#!/bin/sh\necho "$0 $*" >>%s/calls\n' "$t" >"$t/bin/systemd-tmpfiles"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
calls() { cat "$t/calls" 2>/dev/null; rm -f "$t/calls"; }
# shellcheck source=/dev/null
pac() { (set +e; . "$here/packages/$1/$1.install"; "$2"); }
pam='-password   optional     pam_gnome_keyring.so'

# agros-system
echo 'password include system-auth' >"$r/etc/pam.d/passwd"
pac agros-system post_install
pac agros-system post_install
[[ $(grep -cxF -- "$pam" "$r/etc/pam.d/passwd") == 1 ]] || fail "passwd's PAM not given the keyring's line once: $(cat "$r/etc/pam.d/passwd")"
c=$(calls)
[[ $(grep -c '^systemctl enable .*agros-wired-link.service' <<<"$c") == 2 && $c == *"--global mask gnome-keyring-daemon"* ]] ||
    fail "the services not enabled at install: $c"
# (Passim, fwupd's LAN cache and listener, masked once: an unmask of yours stays)
[[ $(grep -c '^systemctl mask passim.service$' <<<"$c") == 1 && -e $r/var/lib/agros/passim-masked ]] || fail "Passim not masked once: $c"
# Upgrade: the watch on where it never ran, not where it has (one turned off since stays off); marked only if running
pac agros-system post_upgrade
c=$(calls)
[[ $(grep -c 'enable --now agros-wired-link.service' <<<"$c") == 1 && $c != *Markers* ]] || fail "first upgrade: $c"
mkdir -p "$r/var/lib/agros/wired-link"; touch "$t/active"
pac agros-system post_upgrade
c=$(calls)
[[ $c != *enable* && $c == *"set-property agros-wired-link.service Markers=+needs-restart"* ]] || fail "later upgrade: $c"
pac agros-system post_remove
[[ $(calls) == *"systemctl unmask passim.service"* && ! -e $r/var/lib/agros/passim-masked ]] || fail "Passim not put back at removal"
pac agros-system pre_remove
[[ $(cat "$r/etc/pam.d/passwd") == 'password include system-auth' ]] || fail "the keyring's line left in passwd's PAM"
c=$(calls)
[[ $c == *"disable --now auto-update.service"* && $c == *"disable --now agros-wired-link.service"* &&
    $c != *"disable --now auto-update-install"* && $c == *"--global unmask"* ]] || fail "removal's services: $c"

# agros-camera-switch
pac agros-camera-switch post_install
[[ $(calls) == *"systemctl enable camera-switch.service"* ]] || fail "the switch not enabled"
pac agros-camera-switch post_upgrade
[[ $(calls) == *"set-property camera-switch.service Markers=+needs-restart"* ]] || fail "the running switch not marked"
rm "$t/active"
pac agros-camera-switch post_upgrade
[[ $(calls) != *Markers* ]] || fail "a stopped switch marked"
pac agros-camera-switch pre_remove
[[ $(calls) == *"disable --now camera-switch.service"* ]] || fail "the switch not turned off"
cam=$r/sys/bus/usb/devices/1-6 other=$r/sys/bus/usb/devices/1-7
mkdir -p "$cam" "$other"
printf '04f2\n' >"$cam/idVendor"; printf 'b83e\n' >"$cam/idProduct"; echo 0 >"$cam/authorized"
printf '04f2\n' >"$other/idVendor"; printf '0001\n' >"$other/idProduct"; echo 0 >"$other/authorized"
pac agros-camera-switch post_remove
[[ ! -e $r/var/lib/camera-switch ]] || fail "the switch's saved position left"
[[ $(cat "$cam/authorized") == 1 && $(cat "$other/authorized") == 0 ]] || fail "the camera not put back at removal (or another device touched)"
echo "ok services-install"
