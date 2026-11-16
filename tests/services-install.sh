#!/usr/bin/env bash
# agros-system's and agros-camera-switch's install scripts (packages/*/*.install) in a throwaway root (AGROS_ROOT), a
# systemctl stand-in: the services on at install, passwd's PAM given the keyring's line once and back at removal,
# pacman.conf the upstream gate's Include likewise, and [agros]'s SigLevel (its database's signature required); a
# running camera switch marked for systemd's restart, a stopped one not; the switch's saved position gone at removal,
# the camera put back
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
# (a line of yours naming another file, and one commented out: neither the gate's Include; the ISO's NoExtract line,
# and one of yours)
printf '%s\n' '[options]' 'NoExtract = usr/share/doc/* usr/share/hypr/wall*.png # agros-iso' 'Architecture = auto' \
    'NoExtract = usr/share/mine/*' '#Include = /etc/pacman.d/agros-gate.conf' 'Include = /etc/pacman.d/agros-gate.conf.old' '' \
    '[core]' 'SigLevel = Optional' 'Include = /etc/pacman.d/mirrorlist' '' '[agros]' 'Server = https://crimzoagra.github.io/agros/$arch' \
    '' '[later]' 'SigLevel = Required DatabaseRequired' 'Server = file:///srv/later' >"$r/etc/pacman.conf"
pac agros-system post_install
pac agros-system post_install
# (the upstream gate's file and the files never unpacked, this package's, each included by pacman.conf once, in
# [options], the ISO's copy of the list gone, yours kept; gone again at removal. [agros]'s database signature required,
# once, under [agros]: another section's SigLevel isn't its, before it or after)
[[ $(cat "$r/etc/pacman.conf") == $'[options]\nInclude = /etc/pacman.d/agros-noextract.conf\nInclude = /etc/pacman.d/agros-gate.conf\nArchitecture = auto\nNoExtract = usr/share/mine/*\n#Include = /etc/pacman.d/agros-gate.conf\nInclude = /etc/pacman.d/agros-gate.conf.old\n\n[core]\nSigLevel = Optional\nInclude = /etc/pacman.d/mirrorlist\n\n[agros]\nSigLevel = Required DatabaseRequired\nServer = https://crimzoagra.github.io/agros/$arch\n\n[later]\nSigLevel = Required DatabaseRequired\nServer = file:///srv/later' ]] ||
    fail "pacman.conf not given the gate's and the NoExtract list's Includes once, in [options], the ISO's line out, [agros]'s SigLevel once: $(cat "$r/etc/pacman.conf")"
[[ $(grep -cxF -- "$pam" "$r/etc/pam.d/passwd") == 1 ]] || fail "passwd's PAM not given the keyring's line once: $(cat "$r/etc/pam.d/passwd")"
c=$(calls)
[[ $(grep -c '^systemctl enable .*auto-update-install.service' <<<"$c") == 2 && $c == *"--global mask gnome-keyring-daemon"* ]] ||
    fail "the services not enabled at install: $c"
# (Passim, fwupd's LAN cache and listener, masked once: an unmask of yours stays)
[[ $(grep -c '^systemctl mask passim.service$' <<<"$c") == 1 && -e $r/var/lib/agros/passim-masked ]] || fail "Passim not masked once: $c"
# (a machine installed before the list and [agros]'s SigLevel: given both at the upgrade)
sed -i -e '/agros-noextract/d' -e '/^\[agros\]$/,/^$/{/^SigLevel = Required DatabaseRequired$/d}' "$r/etc/pacman.conf"
pac agros-system post_upgrade
[[ $(grep -cx 'Include = /etc/pacman.d/agros-noextract.conf' "$r/etc/pacman.conf") == 1 ]] ||
    fail "the NoExtract list's Include not added at upgrade: $(cat "$r/etc/pacman.conf")"
[[ $(sed -n '/^\[agros\]$/{n;p}' "$r/etc/pacman.conf") == 'SigLevel = Required DatabaseRequired' ]] ||
    fail "[agros]'s SigLevel not added at upgrade: $(cat "$r/etc/pacman.conf")"
[[ $(calls) != *enable* ]] || fail "post_upgrade turned something on"
# (a note after it, by hand: the line still found, as at install)
sed -i 's|^Include = /etc/pacman.d/agros-gate.conf$|& # mine|' "$r/etc/pacman.conf"
# (found as it is, by the next install too: not added again)
pac agros-system post_install
[[ $(grep -c '^Include = /etc/pacman.d/agros-gate.conf\( #.*\)\?$' "$r/etc/pacman.conf") == 1 ]] ||
    fail "the gate's Include with a note after it added again: $(cat "$r/etc/pacman.conf")"
pac agros-system post_remove
grep -q '^Include = /etc/pacman.d/agros-gate.conf\( #.*\)\?$' "$r/etc/pacman.conf" && fail "the gate's Include left in pacman.conf at removal"
grep -q 'agros-noextract' "$r/etc/pacman.conf" && fail "the NoExtract list's Include left in pacman.conf at removal"
grep -qx 'NoExtract = usr/share/mine/\*' "$r/etc/pacman.conf" || fail "a NoExtract line of yours taken out at removal"
grep -qx 'Include = /etc/pacman.d/agros-gate.conf.old' "$r/etc/pacman.conf" || fail "a line of yours naming another file taken out at removal"
[[ $(grep -c 'DatabaseRequired' "$r/etc/pacman.conf") == 1 ]] || fail "[agros]'s SigLevel left in pacman.conf at removal, or another section's taken out: $(cat "$r/etc/pacman.conf")"
grep -qx 'SigLevel = Optional' "$r/etc/pacman.conf" || fail "another section's SigLevel taken out at removal"
grep -qx 'Server = https://crimzoagra.github.io/agros/$arch' "$r/etc/pacman.conf" || fail "[agros]'s server taken out at removal"
[[ $(calls) == *"systemctl unmask passim.service"* && ! -e $r/var/lib/agros/passim-masked ]] || fail "Passim not put back at removal"
pac agros-system pre_remove
[[ $(cat "$r/etc/pam.d/passwd") == 'password include system-auth' ]] || fail "the keyring's line left in passwd's PAM"
c=$(calls)
[[ $c == *"disable --now auto-update.service"* &&
    $c != *"disable --now auto-update-install"* && $c == *"--global unmask"* ]] || fail "removal's services: $c"
# (a SigLevel of yours under [agros] stays as it is, none added)
sed -i 's|^\[agros\]$|&\nSigLevel = Optional TrustAll|' "$r/etc/pacman.conf"
pac agros-system post_upgrade
[[ $(sed -n '/^\[agros\]$/,/^$/p' "$r/etc/pacman.conf") == $'[agros]\nSigLevel = Optional TrustAll\nServer = https://crimzoagra.github.io/agros/$arch' ]] ||
    fail "a SigLevel of yours under [agros] not kept as it is: $(cat "$r/etc/pacman.conf")"
calls >/dev/null

# agros-camera-switch (running: is-active says so)
touch "$t/active"
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
