#!/usr/bin/env bash
# agros-boot's install script (packages/agros-boot/agros-boot.install) in a throwaway root (AGROS_ROOT), with its own
# splash-theme, boot-loader and boot-video-mode, boot-menu a stand-in, and the system's tools stand-ins (none of the
# machine's real ones on PATH): boot-menu run at install and noted; an upgrade runs it only when it changed (one that
# failed, or with no note: run again); removal puts GRUB's and Limine's settings back from .agros-orig
# (commented out where boot-menu added them), takes boot-video-mode's video= and the quiet boot's options out (only those
# not there before AgrOS), and the motherboard's wait back.
# splash-theme --update/--remove, boot-loader's one decision (Limine or GRUB), and boot-menu's own edits of GRUB's and
# Limine's settings, the quiet boot's kernel options in both (refused with one of the system's boot tools on PATH).
# The mkinitcpio drop-ins that add Plymouth's hook, and the snapshot overlay's (a booted snapshot writable in RAM), where
# they're missing; that overlay's own script
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
b=$here/packages/agros-boot
r=$t/root
export AGROS_ROOT=$r
mkdir -p "$r/usr/lib/agros/boot-video-mode" "$r/etc/default" "$r/boot" "$t/bin" "$t/sys"
ln -s "$b/splash-theme" "$b/boot-loader" "$r/usr/lib/agros/"
# (copied: run through a link, Python looks for screenmode.py beside the file linked to)
cp "$here/system/boot-video-mode" "$here/.local/share/caelestia-greeter/screenmode.py" "$r/usr/lib/agros/boot-video-mode/"
# Only these of the system's tools (no real grub-mkconfig, mkinitcpio, limine-* or efibootmgr found by command -v)
for x in bash sh env sed grep cat cp rm mkdir sha256sum python3 head tail readlink mv dirname cut ln touch chmod cmp ls tee; do
    ln -s "$(command -v "$x")" "$t/sys/$x"
done
export PATH=$t/bin:$t/sys
calls() { cat "$t/calls" 2>/dev/null; }
# Stand-ins, each noting its call: boot-menu ($BOOT_MENU_RC; $1 its version; its note written as the real one writes it),
# the boot tools; plymouth's theme in a file
menu() {
    cat >"$r/usr/lib/agros/boot-menu" <<STANDIN
#!/bin/sh
# v$1
s=$r/var/lib/agros/boot-menu.sum
mkdir -p "\${s%/*}"
echo boot-menu >>$t/calls
rc=\${BOOT_MENU_RC:-0}
if [ \$rc = 0 ]; then sha256sum <"\$0" >"\$s"; elif [ ! -f "\$s" ]; then : >"\$s"; fi
exit \$rc
STANDIN
    chmod +x "$r/usr/lib/agros/boot-menu"
}
for x in grub-mkconfig limine-update efibootmgr systemctl; do
    printf '#!/bin/sh\necho "%s $*" >>%s/calls\n' "$x" "$t" >"$t/bin/$x"
done
printf '#!/bin/sh\necho "mkinitcpio $*" >>%s/calls\nexit ${MKINITCPIO_RC:-0}\n' "$t" >"$t/bin/mkinitcpio"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/pacman"
cat >"$t/bin/plymouth-set-default-theme" <<EOF
#!/bin/sh
case \$1 in "") cat "$t/theme" ;; -r) echo default >"$t/theme" ;; *) echo "\$1" >"$t/theme" ;; esac
EOF
printf '#!/bin/sh\necho ext4\n' >"$t/bin/findmnt"
chmod +x "$t/bin/"*
# (and checked: each boot tool these scripts run is its stand-in here, never the machine's)
for x in grub-mkconfig limine-update efibootmgr systemctl mkinitcpio findmnt pacman; do
    [[ $(command -v "$x") == "$t/bin/$x" ]] || fail "$x isn't the stand-in: $(command -v "$x")"
done
for x in snapper limine-mkinitcpio; do ! command -v "$x" >/dev/null || fail "$x found: $(command -v "$x")"; done
# shellcheck source=../packages/agros-boot/agros-boot.install
. "$b/agros-boot.install"
stamp=$r/var/lib/agros/boot-menu.sum
# (as pacman runs them: without set -e)
pac() { (set +e; "$@"); }
sum() { sha256sum <"$r/usr/lib/agros/boot-menu"; }

# boot-loader: neither; GRUB (its settings and grub-mkconfig); Limine's settings win over GRUB's left behind; Limine
# installed without GRUB's tools
mv "$t/bin/grub-mkconfig" "$t/gm"
"$b/boot-loader" && fail "boot-loader found a loader with none there"
echo 'GRUB_TIMEOUT=5' >"$r/etc/default/grub"
"$b/boot-loader" && fail "GRUB without grub-mkconfig taken for the boot loader"
printf '#!/bin/sh\n[ "$1 $2" = "-Q limine" ]\n' >"$t/bin/pacman"
[[ $("$b/boot-loader") == limine ]] || fail "Limine installed without GRUB's tools not taken for the boot loader"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/pacman"
mv "$t/gm" "$t/bin/grub-mkconfig"
[[ $("$b/boot-loader") == grub ]] || fail "GRUB not found"
touch "$r/etc/default/limine"
[[ $("$b/boot-loader") == limine ]] || fail "Limine's settings not taken over GRUB's"
"$b/boot-loader" --limine && fail "a limine.conf found where there's none"
mkdir -p "$r/boot/EFI/limine" && touch "$r/boot/EFI/limine/limine.conf"
[[ $("$b/boot-loader" --limine) == "$r/boot/EFI/limine/limine.conf" ]] || fail "limine.conf not found: $("$b/boot-loader" --limine)"
rm -r "$r/etc/default/limine" "$r/boot/EFI"

# Install: boot-menu run and noted (its version); failed: an empty note, run again at the next upgrade, then noted
menu 1
rm -f "$t/calls"; pac post_install >/dev/null
[[ $(calls | head -1) == boot-menu && $(cat "$stamp") == "$(sum)" ]] || fail "install: boot-menu not run and noted: $(calls)"
rm -f "$stamp" "$t/calls"
BOOT_MENU_RC=1 pac post_install >/dev/null
[[ -f $stamp && ! -s $stamp ]] || fail "a failed boot-menu not noted as not done"
rm -f "$t/calls"; pac post_upgrade >/dev/null
[[ $(calls | grep -c boot-menu) == 1 && $(cat "$stamp") == "$(sum)" ]] || fail "a failed install's boot-menu not run again: $(calls)"
# Upgrade: the same boot-menu not run; a changed one run; one with no note run
rm -f "$t/calls"; pac post_upgrade >/dev/null
grep -q boot-menu <<<"$(calls)" && fail "an unchanged boot-menu run again"
menu 2
pac post_upgrade >/dev/null
[[ $(calls | grep -c boot-menu) == 1 && $(cat "$stamp") == "$(sum)" ]] || fail "a changed boot-menu not run: $(calls)"
rm -f "$stamp" "$t/calls"; menu 3
pac post_upgrade >/dev/null
[[ $(calls | grep -c boot-menu) == 1 && $(cat "$stamp") == "$(sum)" ]] || fail "boot-menu with no note not run: $(calls)"

menu 5; "$r/usr/lib/agros/boot-menu"

# Removal, GRUB: boot-menu's settings back as .agros-orig had them (one it added: commented out), "quiet" out where it
# added it, boot-video-mode's video= out, the menu made once, the motherboard's wait back, the note gone
printf '%s\n' 'GRUB_TIMEOUT_STYLE=menu' 'GRUB_TIMEOUT=5' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog splash'" '#GRUB_DISABLE_OS_PROBER=false' \
    'GRUB_THEME="/usr/share/grub/themes/cachyos/theme.txt"' >"$r/etc/default/grub.agros-orig"
printf '%s\n' 'GRUB_TIMEOUT_STYLE=hidden' 'GRUB_TIMEOUT=1' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog splash video=HDMI-A-1:1920x1080@60 quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=false'" \
    'GRUB_DISABLE_OS_PROBER=false' 'GRUB_THEME=/usr/share/grub/themes/agros/theme.txt' 'GRUB_DEFAULT=0' >"$r/etc/default/grub"
mkdir -p "$r/var/lib/agros" && echo 5 >"$r/var/lib/agros/efi-timeout"
rm -f "$t/calls"; pac pre_remove >/dev/null
want=$(printf '%s\n' 'GRUB_TIMEOUT_STYLE=menu' 'GRUB_TIMEOUT=5' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog splash'" '#GRUB_DISABLE_OS_PROBER=false' \
    'GRUB_THEME="/usr/share/grub/themes/cachyos/theme.txt"' '#GRUB_DEFAULT=0')
[[ $(cat "$r/etc/default/grub") == "$want" ]] || fail "GRUB's settings not put back: $(cat "$r/etc/default/grub")"
[[ ! -e $r/etc/default/grub.agros-orig && ! -e $stamp && ! -e $r/var/lib/agros/efi-timeout ]] || fail "removal left its notes"
[[ $(calls | grep -c grub-mkconfig) == 1 ]] && grep -qx 'efibootmgr -q -t 5' <<<"$(calls)" || fail "removal's calls: $(calls)"

# Removal, Limine: limine.conf's settings back, the video= out of /etc/default/limine and its entries made again, no GRUB
rm "$r/etc/default/grub"
echo 'KERNEL_CMDLINE[default]+="video=DP-1:2560x1440@165 quiet video=efifb:off"' >"$r/etc/default/limine"
mkdir -p "$r/boot/limine"
printf '%s\n' 'timeout: 5' '/CachyOS' >"$r/boot/limine/limine.conf.agros-orig"
printf '%s\n' 'remember_last_entry: no' 'quiet: yes' 'timeout: 1' '/CachyOS' >"$r/boot/limine/limine.conf"
rm -f "$t/calls"; pac pre_remove >/dev/null
[[ $(cat "$r/boot/limine/limine.conf") == "$(printf '%s\n' '#remember_last_entry: no' '#quiet: yes' 'timeout: 5' '/CachyOS')" ]] ||
    fail "Limine's settings not put back: $(cat "$r/boot/limine/limine.conf")"
[[ $(cat "$r/etc/default/limine") == 'KERNEL_CMDLINE[default]+="quiet video=efifb:off"' ]] ||
    fail "its video= not taken out (or the user's own too): $(cat "$r/etc/default/limine")"
grep -q '^limine-update' <<<"$(calls)" && ! grep -q grub-mkconfig <<<"$(calls)" || fail "Limine's removal calls: $(calls)"
[[ ! -e $r/boot/limine/limine.conf.agros-orig ]] || fail "limine.conf.agros-orig left"
# The quiet boot's options out of /etc/default/limine where its limine.agros-orig hadn't them (its own loglevel kept), the
# entries made again, the copy gone
echo 'KERNEL_CMDLINE[default]+="loglevel=5 nowatchdog"' >"$r/etc/default/limine.agros-orig"
echo 'KERNEL_CMDLINE[default]+="loglevel=5 nowatchdog quiet splash rd.udev.log_level=3 systemd.show_status=false"' >"$r/etc/default/limine"
rm -f "$t/calls"; pac pre_remove >/dev/null
[[ $(cat "$r/etc/default/limine") == 'KERNEL_CMDLINE[default]+="loglevel=5 nowatchdog"' && ! -e $r/etc/default/limine.agros-orig ]] ||
    fail "the quiet boot's options not taken out of Limine's: $(cat "$r/etc/default/limine")"
grep -q '^limine-update' <<<"$(calls)" || fail "Limine's entries not made again after the quiet boot's options came out: $(calls)"
# boot-video-mode --remove: none there, exit 3; no boot loader, exit 3
rc=0; "$r/usr/lib/agros/boot-video-mode/boot-video-mode" --remove || rc=$?
((rc == 3)) || fail "boot-video-mode --remove with nothing to take out: exit $rc"
rm "$r/etc/default/limine"
rc=0; "$r/usr/lib/agros/boot-video-mode/boot-video-mode" --remove || rc=$?
((rc == 3)) || fail "boot-video-mode --remove with no boot loader: exit $rc"

# splash-theme: made from CachyOS's (titles in the system's language) and set; --update makes the boot images again
# only when it changed and is in use; --remove puts CachyOS's back and takes the theme away, even when the boot images
# fail (then said in its exit status)
src=$r/usr/share/plymouth/themes/cachyos-bootanimation dst=$r/usr/share/plymouth/themes/cachyos-bootanimation-fast
mkdir -p "$src"
printf '%s\n' '[Plymouth Theme]' 'Name=cachyos-bootanimation' '[boot-up]' 'UseEndAnimation=true' '[shutdown]' '[reboot]' \
    >"$src/cachyos-bootanimation.plymouth"
echo 'LANG=pt_PT.UTF-8' >"$r/etc/locale.conf"
echo cachyos-bootanimation >"$t/theme"
rm -f "$t/calls"; "$b/splash-theme" >/dev/null
f=$dst/cachyos-bootanimation-fast.plymouth
grep -qx 'Name=cachyos-bootanimation-fast' "$f" && grep -qx 'UseEndAnimation=false' "$f" && grep -qx '_Title=A encerrar...' "$f" ||
    fail "the faster splash not made: $(cat "$f")"
[[ $(cat "$t/theme") == cachyos-bootanimation-fast && $(calls) == "mkinitcpio -P" ]] || fail "not set, or no boot images: $(calls)"
rm -f "$t/calls"; "$b/splash-theme" --update; [[ -z $(calls) ]] || fail "--update unchanged made the boot images"
echo 'LANG=de_DE.UTF-8' >"$r/etc/locale.conf"
"$b/splash-theme" --update; [[ $(calls) == "mkinitcpio -P" ]] || fail "--update changed and in use: no boot images"
echo cachyos-bootanimation >"$t/theme"; echo 'LANG=fr_FR.UTF-8' >"$r/etc/locale.conf"; rm -f "$t/calls"
"$b/splash-theme" --update; [[ -z $(calls) ]] || fail "--update not in use made the boot images"
grep -q 'Arrêt' "$f" || fail "--update didn't make the theme again"
echo cachyos-bootanimation-fast >"$t/theme"
rc=0; MKINITCPIO_RC=1 "$b/splash-theme" --remove || rc=$?
((rc == 1)) && [[ ! -e $dst && $(cat "$t/theme") == cachyos-bootanimation ]] ||
    fail "--remove with the boot images failing: exit $rc, theme $(cat "$t/theme"), $(ls "$dst" 2>&1)"
mkdir -p "$dst"; rm -f "$t/calls"
"$b/splash-theme" --remove && [[ ! -e $dst && -z $(calls) ]] || fail "--remove, not in use: $(calls)"
# --no-initramfs (agros-boot's install scripts: mkinitcpio's hook makes them after the transaction): set, not made
echo cachyos-bootanimation >"$t/theme"; rm -f "$t/calls"
"$b/splash-theme" --no-initramfs >/dev/null && [[ $(cat "$t/theme") == cachyos-bootanimation-fast && -z $(calls) ]] ||
    fail "--no-initramfs: theme $(cat "$t/theme"), calls $(calls)"
"$b/splash-theme" --remove --no-initramfs && [[ $(cat "$t/theme") == cachyos-bootanimation && -z $(calls) ]] ||
    fail "--remove --no-initramfs: theme $(cat "$t/theme"), calls $(calls)"
# An AMD GPU (chwd --check amd, as CachyOS's installer asks; without chwd, an AMD card in sysfs): CachyOS's plain splash
# (cachyos) kept, not the faster boot animation; the faster one set before moved to it
printf '#!/bin/sh\n[ "$*" = "--check amd" ]\n' >"$t/bin/chwd" && chmod +x "$t/bin/chwd"
echo cachyos >"$t/theme"; rm -f "$t/calls"
"$b/splash-theme" >/dev/null && [[ $(cat "$t/theme") == cachyos && -z $(calls) ]] || fail "AMD: theme $(cat "$t/theme")"
echo cachyos-bootanimation-fast >"$t/theme"
"$b/splash-theme" --update >/dev/null && [[ $(cat "$t/theme") == cachyos && $(calls) == "mkinitcpio -P" ]] ||
    fail "AMD: the faster splash not moved off: theme $(cat "$t/theme"), calls $(calls)"
printf '#!/bin/sh\nexit 1\n' >"$t/bin/chwd"
echo cachyos-bootanimation >"$t/theme"
"$b/splash-theme" --no-initramfs >/dev/null && [[ $(cat "$t/theme") == cachyos-bootanimation-fast ]] || fail "chwd: no AMD, yet not set"
rm "$t/bin/chwd"; mkdir -p "$r/sys/class/drm/card1/device" && echo 0x1002 >"$r/sys/class/drm/card1/device/vendor"
echo cachyos >"$t/theme"
"$b/splash-theme" --no-initramfs >/dev/null && [[ $(cat "$t/theme") == cachyos ]] || fail "AMD in sysfs: theme $(cat "$t/theme")"
rm -r "$r/sys/class"
# boot-menu itself on GRUB: only the lines in use set (CachyOS's commented-out #GRUB_THEME= kept as it is, not made a
# second GRUB_THEME=), the missing ones added, quiet added, GRUB's loading lines out, the menu made, the motherboard's
# wait taken away; its .agros-orig made
rm -f "$t/calls" "$r/etc/default/limine" "$r/etc/default/grub"*; rm -rf "$r/boot/limine" "$r/var/lib/agros"
# (neither boot loader yet: nothing done, and not noted as done, an empty note, so the next update runs it again)
rc=0; bash "$b/boot-menu" >/dev/null || rc=$?
[[ $rc == 1 && -f $r/var/lib/agros/boot-menu.sum && ! -s $r/var/lib/agros/boot-menu.sum ]] ||
    fail "boot-menu with no boot loader taken as done (rc $rc, note: $(cat "$r/var/lib/agros/boot-menu.sum" 2>/dev/null))"
rm -rf "$r/var/lib/agros"
printf '%s\n' 'GRUB_DEFAULT=saved' 'GRUB_TIMEOUT=5' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog'" '#GRUB_THEME="/path/to/gfxtheme"' \
    'GRUB_THEME=/usr/share/grub/themes/cachyos/theme.txt' >"$r/etc/default/grub"
mkdir -p "$r/etc/grub.d" "$r/sys/firmware/efi" "$r/boot/grub" && touch "$r/boot/grub/grub.cfg"
printf '%s\n' "echo '\$message'" 'linux $path' >"$r/etc/grub.d/10_linux"
bash "$b/boot-menu" >/dev/null || fail "boot-menu on GRUB failed"
[[ $(cat "$r/var/lib/agros/boot-menu.sum") == "$(sha256sum <"$b/boot-menu")" ]] || fail "boot-menu didn't note its run"
want=$(printf '%s\n' 'GRUB_DEFAULT=0' 'GRUB_TIMEOUT=1' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false'" '#GRUB_THEME="/path/to/gfxtheme"' \
    'GRUB_THEME=/usr/share/grub/themes/agros/theme.txt' 'GRUB_TIMEOUT_STYLE=hidden' 'GRUB_SAVEDEFAULT=false' 'GRUB_DISABLE_OS_PROBER=false')
[[ $(cat "$r/etc/default/grub") == "$want" ]] || fail "boot-menu's GRUB settings: $(cat "$r/etc/default/grub")"
[[ $(cat "$r/etc/grub.d/10_linux") == 'linux $path' && -f $r/etc/default/grub.agros-orig ]] ||
    fail "GRUB's loading lines left, or no .agros-orig"
grep -qx "grub-mkconfig -o $r/boot/grub/grub.cfg" <<<"$(calls)" && grep -qx 'efibootmgr -q -t 0' <<<"$(calls)" ||
    fail "boot-menu's GRUB calls: $(calls)"
# A settings file with no newline after its last line (an editor that leaves it off): the settings it adds on lines of
# their own, not run onto that one (GRUB_TIMEOUT=1GRUB_TIMEOUT_STYLE=hidden)
printf '%s' 'GRUB_TIMEOUT=5' >"$r/etc/default/grub"; rm -f "$r/etc/default/grub.agros-orig"
bash "$b/boot-menu" >/dev/null || fail "boot-menu on a GRUB file with no last newline failed"
grep -qx 'GRUB_TIMEOUT=1' "$r/etc/default/grub" && grep -qx 'GRUB_TIMEOUT_STYLE=hidden' "$r/etc/default/grub" ||
    fail "a setting run onto the file's last line: $(cat "$r/etc/default/grub")"
# The install: agros-boot's package step runs before GRUB is set up (no /boot/grub/grub.cfg, /etc/default/grub the grub
# package's own): nothing done, no .agros-orig, an empty note. The installer's own step then (after its grubcfg wrote
# CachyOS's settings) runs boot-menu: the .agros-orig is CachyOS's, the run noted. The first upgrade (boot-menu unchanged)
# leaves the boot settings alone (a change of the user's kept)
rm -rf "$r/var/lib/agros" "$r/boot/grub" "$r/etc/default/grub"*; rm -f "$t/calls"
cp "$b/boot-menu" "$r/usr/lib/agros/" && chmod 755 "$r/usr/lib/agros/boot-menu"  # (as installed)
echo 'GRUB_TIMEOUT=5  # stock' >"$r/etc/default/grub"
pac post_install >/dev/null
[[ -f $stamp && ! -s $stamp && ! -e $r/etc/default/grub.agros-orig ]] && grep -qx 'GRUB_TIMEOUT=5  # stock' "$r/etc/default/grub" ||
    fail "boot-menu acted before GRUB was set up: $(ls "$r/etc/default"), $(cat "$r/etc/default/grub")"
! grep -q 'grub-mkconfig\|efibootmgr' <<<"$(calls)" || fail "boot-menu before GRUB was set up: $(calls)"
printf '%s\n' 'GRUB_TIMEOUT=5' "GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog'" 'GRUB_THEME=/usr/share/grub/themes/cachyos/theme.txt' >"$r/etc/default/grub"
cp "$r/etc/default/grub" "$t/cachyos-grub"
mkdir -p "$r/boot/grub" && touch "$r/boot/grub/grub.cfg"
"$r/usr/lib/agros/boot-menu" >/dev/null || fail "the installer's boot-menu failed"
cmp -s "$t/cachyos-grub" "$r/etc/default/grub.agros-orig" && [[ $(cat "$stamp") == "$(sum)" ]] ||
    fail "the installer's boot-menu: .agros-orig not CachyOS's, or not noted"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' "$r/etc/default/grub"; rm -f "$t/calls"
pac post_upgrade >/dev/null
grep -qx 'GRUB_TIMEOUT=3' "$r/etc/default/grub" && ! grep -q grub-mkconfig <<<"$(calls)" ||
    fail "the first upgrade after the install ran boot-menu again: $(calls)"
rm "$r/usr/lib/agros/boot-menu"
# On Limine: its three settings set (the missing ones before the entries), its default_entry left as it was, no GRUB
rm -f "$t/calls"; mkdir -p "$r/boot/limine"
printf '%s\n' '# KERNEL_CMDLINE[default]+="x"' 'KERNEL_CMDLINE[default]+="nowatchdog quiet"' 'KERNEL_CMDLINE[default]+="rw"' >"$r/etc/default/limine"
printf '%s\n' 'timeout: 5' 'default_entry: 2' '/+CachyOS' >"$r/boot/limine/limine.conf"
bash "$b/boot-menu" >/dev/null || fail "boot-menu on Limine failed"
want=$(printf '%s\n' 'remember_last_entry: no' 'quiet: yes' 'timeout: 1' 'default_entry: 2' '/+CachyOS')
[[ $(cat "$r/boot/limine/limine.conf") == "$want" && -f $r/boot/limine/limine.conf.agros-orig ]] ||
    fail "boot-menu's Limine settings: $(cat "$r/boot/limine/limine.conf")"
! grep -q grub-mkconfig <<<"$(calls)" || fail "boot-menu on Limine made GRUB's menu: $(calls)"
# Its kernel options: the quiet boot's missing ones added on the last line in effect (its quiet on the first counted), its
# entries made again, the file as it was kept once (limine.agros-orig); run again, nothing to add: the entries not made again
want=$(printf '%s\n' '# KERNEL_CMDLINE[default]+="x"' 'KERNEL_CMDLINE[default]+="nowatchdog quiet"' 'KERNEL_CMDLINE[default]+="rw splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false"')
[[ $(cat "$r/etc/default/limine") == "$want" ]] || fail "the quiet boot's options in Limine's: $(cat "$r/etc/default/limine")"
grep -q '^limine-update' <<<"$(calls)" && grep -qx 'KERNEL_CMDLINE\[default\]+="nowatchdog quiet"' "$r/etc/default/limine.agros-orig" ||
    fail "Limine's entries not made, or its options before AgrOS not kept: $(calls)"
rm -f "$t/calls"; bash "$b/boot-menu" >/dev/null
! grep -q '^limine-update' <<<"$(calls)" || fail "Limine's entries made again with nothing changed"
grep -qx 'KERNEL_CMDLINE\[default\]+="nowatchdog quiet"' "$r/etc/default/limine.agros-orig" || fail "limine.agros-orig overwritten"
# With AGROS_ROOT, a boot tool of the system's (here a link to one) refused before anything is done
mkdir "$t/sysbin" && ln -s "$(readlink -f "$t/sys/cat")" "$t/sysbin/efibootmgr"
cp "$r/boot/limine/limine.conf.agros-orig" "$r/boot/limine/limine.conf"
out=$(PATH=$t/sysbin:$PATH bash "$b/boot-menu") && fail "boot-menu ran with the system's efibootmgr"
[[ $out == *"efibootmgr is the system's"* ]] && cmp -s "$r/boot/limine/limine.conf.agros-orig" "$r/boot/limine/limine.conf" ||
    fail "boot-menu not refused before any change: $out"
# The mkinitcpio drop-in: Plymouth's hook added where missing (before an encrypt hook, else last), never twice
hooks() { bash -c 'read -ra HOOKS <<<"$1"; . "$2"; echo "${HOOKS[*]}"' _ "$1" "$b/mkinitcpio-plymouth.conf"; }
[[ $(hooks "base udev autodetect kms block filesystems fsck") == "base udev autodetect kms block filesystems fsck plymouth" ]] ||
    fail "Plymouth's hook not added last: $(hooks "base udev autodetect kms block filesystems fsck")"
[[ $(hooks "base udev block encrypt filesystems") == "base udev block plymouth encrypt filesystems" ]] ||
    fail "Plymouth's hook not before encrypt: $(hooks "base udev block encrypt filesystems")"
[[ $(hooks "base systemd plymouth sd-encrypt filesystems") == "base systemd plymouth sd-encrypt filesystems" ]] ||
    fail "Plymouth's hook added again"
# An older mkinitcpio.conf's HOOKS as a string: made an array, Plymouth's hook before encrypt
out=$(bash -c 'HOOKS="$1"; . "$2"; declare -p HOOKS' _ "base udev block encrypt filesystems" "$b/mkinitcpio-plymouth.conf")
[[ $out == 'declare -a HOOKS=([0]="base" [1]="udev" [2]="block" [3]="plymouth" [4]="encrypt" [5]="filesystems")' ]] ||
    fail "string HOOKS: $out"

# A snapshot booted from the boot menu made writable in RAM. The drop-in, on a Btrfs root: AgrOS's hook in a systemd boot
# image where none it runs is there (grub-btrfs's busybox one doesn't count there: CachyOS's installer drops it anyway),
# grub-btrfs's in a busybox one where it's installed; never twice, nor beside Limine's, nor on another filesystem
# (findmnt's stand-in: $ROOT_FS, else btrfs)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\necho "${ROOT_FS:-btrfs}"\n' >"$t/bin/findmnt"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "ro=${RO:-true}"\n' >"$t/bin/btrfs"
printf '#!/bin/sh\nmkdir -p %s/ram && echo %s/ram\n' "$t" "$t" >"$t/bin/mktemp"
printf '#!/bin/sh\necho "mount $*" >>%s/calls\n' "$t" >"$t/bin/mount"
chmod +x "$t/bin/findmnt" "$t/bin/btrfs" "$t/bin/mktemp" "$t/bin/mount"
snap() { bash -c 'read -ra HOOKS <<<"$1"; . "$2"; echo "${HOOKS[*]}"' _ "$1" "$b/mkinitcpio-snapshot-overlay.conf"; }
sd="base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems"
[[ $(snap "$sd") == "$sd agros-snapshot-overlay" ]] || fail "the snapshot hook not added to a systemd image: $(snap "$sd")"
[[ $(snap "$sd grub-btrfs-overlayfs") == "$sd grub-btrfs-overlayfs agros-snapshot-overlay" ]] ||
    fail "grub-btrfs's busybox hook taken for one a systemd image runs: $(snap "$sd grub-btrfs-overlayfs")"
for h in sd-btrfs-overlayfs agros-snapshot-overlay; do
    [[ $(snap "$sd $h") == "$sd $h" ]] || fail "a snapshot hook added beside $h: $(snap "$sd $h")"
done
export ROOT_FS=ext4
[[ $(snap "$sd") == "$sd" ]] || fail "the snapshot hook added on a root that isn't Btrfs: $(snap "$sd")"
unset ROOT_FS
bb="base udev autodetect block filesystems fsck"
want=$bb
[[ ! -e /usr/lib/initcpio/install/grub-btrfs-overlayfs ]] || want+=" grub-btrfs-overlayfs"
[[ $(snap "$bb") == "$want" ]] || fail "a busybox image's snapshot hook: $(snap "$bb") (grub-btrfs's, only where installed)"
[[ $(snap "$bb btrfs-overlayfs") == "$bb btrfs-overlayfs" ]] || fail "a snapshot hook added beside btrfs-overlayfs"
# (an older mkinitcpio.conf's HOOKS as a string)
[[ $(bash -c 'HOOKS="$1"; . "$2"; echo "${#HOOKS[@]}"' _ "$sd" "$b/mkinitcpio-snapshot-overlay.conf") == 12 ]] ||
    fail "string HOOKS not made an array with the snapshot hook"
# Its script, in the boot image: a read-only Btrfs root gets an overlay in RAM; a writable one, or another filesystem, not
rm -f "$t/calls"
bash "$b/snapshot-overlay" >/dev/null || fail "the snapshot overlay's script failed"
[[ $(calls) == "mount -t tmpfs snapshot-overlay $t/ram"$'\n'"mount -t overlay overlay -o lowerdir=/sysroot,upperdir=$t/ram/upper,workdir=$t/ram/work /sysroot" &&
    -d $t/ram/upper && -d $t/ram/work ]] || fail "a read-only snapshot not overlaid: $(calls)"
for env in RO=false ROOT_FS=ext4; do
    rm -f "$t/calls"
    env "$env" bash "$b/snapshot-overlay" >/dev/null || fail "the snapshot overlay's script failed ($env)"
    [[ -z $(calls) ]] || fail "overlaid with $env: $(calls)"
done
# The hook's files are the package's: the hook under the name the drop-in adds, its script and unit where it takes them
pkg=$(cat "$b/PKGBUILD")
for f in /usr/lib/initcpio/install/agros-snapshot-overlay /usr/lib/agros/snapshot-overlay /usr/lib/agros/snapshot-overlay.service; do
    grep -qF "\"\$pkgdir$f\"" <<<"$pkg" || fail "agros-boot doesn't install $f"
done
grep -qx '    add_file /usr/lib/agros/snapshot-overlay /usr/lib/agros/snapshot-overlay 755' "$b/snapshot-overlay-hook" &&
    grep -q '^    add_file /usr/lib/agros/snapshot-overlay.service /usr/lib/systemd/system/agros-snapshot-overlay.service ' "$b/snapshot-overlay-hook" &&
    grep -qx 'ExecStart=/usr/lib/agros/snapshot-overlay' "$b/snapshot-overlay.service" ||
    fail "the snapshot hook's script or unit not where it takes them from"
echo "ok agros-boot-install"
