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
# (and Thunar's own wallpaper plugin, unpacked before the NoExtract list named it, gone: two "Set as wallpaper" else;
# Thunar's other plugins kept)
p=$r/usr/lib/thunarx-3 && mkdir -p "$p" "$r/etc/pacman.d" && touch "$p/thunar-wallpaper-plugin.so" "$p/thunar-uca.so"
cp "$here/packages/agros-system/agros-noextract.conf" "$r/etc/pacman.d/"
pac post_upgrade
[[ ! -e $p/thunar-wallpaper-plugin.so && -e $p/thunar-uca.so ]] || fail "Thunar's own wallpaper plugin left: $(ls "$p")"
rm -r "${r:?}/etc/pacman.d" "${r:?}/usr"

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

# Its files in /etc are backup files (one you edited kept at an upgrade, every commit being one), but for those that
# reach every machine as they are: the upstream gate, the NoExtract list, the sudoers rule (and its folder)
backup=$(cd "$here/packages/agros-system" && startdir=$PWD bash -c '. ./PKGBUILD && printf "%s\n" "${backup[@]}"')
[[ -n $backup ]] || fail "agros-system's backup= not read"
etc=$(grep -o '"$pkgdir/etc/[^"]*"' "$here/packages/agros-system/PKGBUILD" | sed 's|^"$pkgdir/||; s|"$||')
[[ -n $etc ]] || fail "agros-system's files in /etc not found in its PKGBUILD"
for f in $etc; do
    case $f in etc/pacman.d/agros-gate.conf | etc/pacman.d/agros-noextract.conf | etc/sudoers.d | etc/sudoers.d/*) continue ;; esac
    grep -qxF -- "$f" <<<"$backup" || fail "agros-system's /$f isn't a backup file: an edit of yours lost at every upgrade"
done

# The NoExtract list leaves out the pointer's other Bibata styles, never the one the desktop (hypr-vars.lua) and the
# login screen (agros-greeter) use: changed there alone, the pointer would have no theme
cursor=$(sed -n 's/^ *cursorTheme = "\([^"]*\)",$/\1/p' "$here/.config/caelestia/hypr-vars.lua")
[[ -n $cursor ]] || fail "the desktop's pointer not found in hypr-vars.lua"
grep -q "XCURSOR_THEME=$cursor " "$here/packages/agros-greeter/run" && grep -qF "Inherits=$cursor\\n" "$here/packages/agros-greeter/PKGBUILD" ||
    fail "the login screen's pointer isn't the desktop's, $cursor"
grep -qx "NoExtract = usr/share/icons/Bibata-\* !usr/share/icons/$cursor/\*" "$here/packages/agros-system/agros-noextract.conf" ||
    fail "the NoExtract list doesn't keep the desktop's pointer, $cursor: $(grep Bibata "$here/packages/agros-system/agros-noextract.conf")"

# The sudoers rule (papirus-folders without a password, as Caelestia calls it): sudo's own parser reads it, and its one
# command runs from / (papirus-folders takes a "Papirus" theme in the folder it's run from, which for a caller's own
# folder was root changing the caller's files). Read as sudo reads it where its tools are here (cvtsudoers)
rule=$here/system/sudoers/agros-papirus-folders
if command -v cvtsudoers >/dev/null; then
    spec=$(cvtsudoers -f json "$rule" 2>&1) || fail "sudo can't read the sudoers rule: $spec"
    [[ $(jq -c '[.User_Specs[].Cmnd_Specs[] | {c: [.Commands[].command], o: .Options}]' <<<"$spec") == \
        '[{"c":["/usr/bin/papirus-folders ^-C [a-z]+ -u$"],"o":[{"runcwd":"/"},{"authenticate":false}]}]' ]] ||
        fail "the sudoers rule isn't papirus-folders alone, without a password, run from /: $spec"
else
    grep -qx '%wheel ALL=(root) CWD=/ NOPASSWD: /usr/bin/papirus-folders ^-C \[a-z\]+ -u\$' "$rule" ||
        fail "the sudoers rule isn't papirus-folders alone, without a password, run from /: $(grep -v '^#' "$rule")"
fi
echo "ok agros-system-install"
