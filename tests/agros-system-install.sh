#!/usr/bin/env bash
# agros-system's install script (packages/agros-system/agros-system.install) and pacman.conf, in a throwaway root
# (AGROS_ROOT), its tools stand-ins: the install adds the upstream gate's and the NoExtract list's Includes after
# [options] (the ISO's copy of the list, "# agros-iso", out once the Include is in), and [agros]'s database signature
# and its mirror (a SigLevel of yours kept, a commented-out mirror line of yours counted); run again, nothing changes.
# An upgrade adds what an older AgrOS lacked, the gate's Include too (a machine from before the gate, or a pacman.conf
# whose .pacnew was merged, took Hyprland unchecked from a manual pacman -Syu). Removal takes out only what it added.
# The passwords keyring's line in passwd's PAM added once and taken out at removal
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/root
export AGROS_ROOT=$r
mkdir -p "$r/etc/pam.d" "$t/bin"
for x in systemctl ufw; do printf '#!/bin/sh\necho "%s $*" >>%s/calls\n' "$x" "$t" >"$t/bin/$x"; done
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
# shellcheck source=../packages/agros-system/agros-system.install
. "$here/packages/agros-system/agros-system.install"
# (as pacman runs them: without set -e)
pac() { (set +e; "$@"); }
conf=$r/etc/pacman.conf
mirror='Server = https://pub-f1a3a482900748e8b69cd81361ab96e1.r2.dev/repo/$arch'
# A new install's pacman.conf as agros-iso leaves it: the NoExtract list's ISO copy, [agros] with its first server
cachyos() {
    printf '%s\n' '[options]' 'HoldPkg = pacman glibc' 'NoExtract = usr/share/doc/* # agros-iso' 'Architecture = auto' '' \
        '[agros]' 'Server = https://crimzoagra.github.io/agros/$arch' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' >"$conf"
}
want=$(printf '%s\n' '[options]' 'Include = /etc/pacman.d/agros-noextract.conf' 'Include = /etc/pacman.d/agros-gate.conf' \
    'HoldPkg = pacman glibc' 'Architecture = auto' '' '[agros]' 'SigLevel = Required DatabaseRequired' \
    'Server = https://crimzoagra.github.io/agros/$arch' "$mirror" '' '[core]' 'Include = /etc/pacman.d/mirrorlist')

# Install: both Includes, the ISO's NoExtract line gone, [agros]'s signature and mirror; again (install, upgrade): the same
cachyos
echo 'password required pam_unix.so' >"$r/etc/pam.d/passwd"
pac post_install
[[ $(cat "$conf") == "$want" ]] || fail "pacman.conf after the install: $(cat "$conf")"
grep -qx -- '-password   optional     pam_gnome_keyring.so' "$r/etc/pam.d/passwd" || fail "the keyring's line not in passwd's PAM"
pac post_install; pac post_upgrade
[[ $(cat "$conf") == "$want" ]] || fail "pacman.conf changed by a second run: $(cat "$conf")"
[[ $(grep -c pam_gnome_keyring "$r/etc/pam.d/passwd") == 1 ]] || fail "the keyring's line added twice"

# Upgrade from an AgrOS before the gate, the NoExtract list and [agros]'s mirror (or a pacman.conf.pacnew merged in):
# all of them added, the gate's Include too
printf '%s\n' '[options]' 'HoldPkg = pacman glibc' 'NoExtract = usr/share/doc/* # agros-iso' 'Architecture = auto' '' \
    '[agros]' 'Server = https://crimzoagra.github.io/agros/$arch' '' '[core]' 'Include = /etc/pacman.d/mirrorlist' >"$conf"
pac post_upgrade
grep -qx 'Include = /etc/pacman.d/agros-gate.conf' "$conf" ||
    fail "an upgrade didn't add the upstream gate's Include (Hyprland not held from a manual pacman -Syu): $(cat "$conf")"
[[ $(cat "$conf") == "$want" ]] || fail "pacman.conf after an upgrade from an older AgrOS: $(cat "$conf")"

# Yours kept: [agros]'s own SigLevel, the mirror commented out (not added again), an Include of the gate's with a comment
printf '%s\n' '[options]' 'Include = /etc/pacman.d/agros-gate.conf  # mine' 'Architecture = auto' '' '[agros]' \
    'SigLevel = Optional' 'Server = https://crimzoagra.github.io/agros/$arch' "#$mirror" >"$conf"
cp "$conf" "$t/mine"
pac post_upgrade
[[ $(cat "$conf") == "$(sed '1a Include = /etc/pacman.d/agros-noextract.conf' "$t/mine")" ]] ||
    fail "a setting of yours changed or added again: $(cat "$conf")"

# Removal: the Includes and what it added to [agros] out, the rest as it was; passwd's PAM line out
cachyos
pac post_install
pac pre_remove; pac post_remove >/dev/null
[[ $(cat "$conf") == "$(printf '%s\n' '[options]' 'HoldPkg = pacman glibc' 'Architecture = auto' '' '[agros]' \
    'Server = https://crimzoagra.github.io/agros/$arch' '' '[core]' 'Include = /etc/pacman.d/mirrorlist')" ]] ||
    fail "pacman.conf after the removal: $(cat "$conf")"
[[ $(cat "$r/etc/pam.d/passwd") == 'password required pam_unix.so' ]] || fail "the keyring's line left in passwd's PAM"
echo "ok agros-system-install"
