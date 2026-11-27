#!/usr/bin/env bash
# boot-trial (agros-boot): armed after an update with the filesystem, the root's and snapshot's subvolumes, the kernel,
# its boot images (microcode first) and this boot's options (GRUB's file: real grub-editenv), an older one cleared
# first; not armed where GRUB's menu doesn't count, the login screen isn't AgrOS's, or the snapshot's boot image has no
# boot-rollback. Each boot: one GRUB didn't count (no agros.trial) not watched; the login screen up stops the count; the
# desktop up clears it; a session without its shell told, not restarted, its second time setting the count to 0;
# sessions crashing at the login screen restart the PC; a login screen that never comes up restarts it; a failure that
# can't be written down clears it; the boot GRUB brought the snapshot back on says whether it came. And GRUB's menu
# script (01_agros-trial) is valid GRUB script
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v grub-editenv >/dev/null || { skipped "no grub-editenv"; exit 0; }
bt=$here/packages/agros-boot/boot-trial
# GRUB's menu script: valid
if command -v grub-script-check >/dev/null; then
    sh "$here/packages/agros-boot/grub-agros-trial" >"$t/trial.cfg" && grub-script-check "$t/trial.cfg" || fail "01_agros-trial isn't valid GRUB script"
fi
export BOOT_TRIAL_ENV=$t/esp/EFI/agros/trial.env BOOT_TRIAL_GRUB_CFG=$t/grub.cfg BOOT_TRIAL_CMDLINE=$t/cmdline \
    BOOT_TRIAL_GREETD=$t/greetd.toml BOOT_TRIAL_BOOT=$t/boot BOOT_TRIAL_BOOT_ID=$t/boot_id AUTO_UPDATE_DIR=$t/au \
    BOOT_TRIAL_POLL=0
mkdir -p "$t/au" "$t/snap/boot" "$t/boot"
get() { grub-editenv "$BOOT_TRIAL_ENV" list | sed -n "s/^$1=//p"; }
# Stand-ins: btrfs (the snapshot's path from the top), findmnt (the root's UUID, a Btrfs root), lsinitcpio (the
# snapshot's boot image's files: $t/image), systemctl (the restart, noted), setpriv (a user told: noted), sleep (the
# clock: one tick a look) and ps (the processes at that tick: the last $t/ps.<tick> file at or before it,
# "<pid>[:<parent>] <user> <command line>" a line, in the forms boot-trial asks for)
stub btrfs 'echo "@/.snapshots/5/snapshot"'
stub findmnt 'case " $* " in *" UUID "*) echo 1234-abcd ;; *" FSTYPE "*) echo btrfs ;; esac'
stub lsinitcpio "cat $t/image"
stub systemctl "echo \"systemctl \$*\" >>$t/calls"
stub setpriv "echo \"told \${*: -1}\" >>$t/calls"
stub sleep "echo \$((\$(cat $t/clock 2>/dev/null || echo 0) + 1)) >$t/clock"
stub ps "n=\$(cat $t/clock 2>/dev/null || echo 0); f=; for ((k = 0; k <= n; k++)); do [[ -f $t/ps.\$k ]] && f=$t/ps.\$k; done
[[ -n \$f ]] || exit 0
case \$* in
    *comm=*) awk '{ split(\$1, p, \":\"); print p[1], (p[2] == \"\" ? 1 : p[2]), \$2, \$3 }' \"\$f\" ;;
    *) cut -d' ' -f2- \"\$f\" ;;
esac"
export PATH=$t/bin:$PATH
# timeline <tick>=<processes, ";" between two> ...
timeline() { rm -f "$t"/ps.* "$t/clock" "$t/calls"; local a; for a; do tr ';' '\n' <<<"${a#*=}" >"$t/ps.${a%%=*}"; done; }
greeter='9 greeter qs -p /etc/greetd/caelestia-greeter'
me=$(id -un)
# watch: boot-trial's, ended (the desktop's watch has no time limit: one that never decides fails here, not hangs)
watch() { local rc=0; timeout 20 "$bt" watch >/dev/null || rc=$?; ((rc != 124)) || fail "the watch never decided"; }
# armed <count>: armed, then the count as GRUB's entry left it (a boot it counted: agros.trial on the line)
armed() { "$bt" arm "$t/snap" >/dev/null || fail "not armed"; grub-editenv "$BOOT_TRIAL_ENV" set "agros_trial=$1"; }

# Armed: the snapshot's subvolume, the root's, the kernel and its boot images (microcode first), this boot's options
# (BOOT_IMAGE and agros.trial out), the count at 2; an older one's leftovers gone
echo 'set agros_trial' >"$t/grub.cfg"
echo 'command = "/etc/greetd/caelestia-greeter/run"' >"$t/greetd.toml"
echo 'BOOT_IMAGE=/@/boot/vmlinuz-linux-cachyos root=UUID=1234-abcd rw rootflags=defaults,subvol=/@ quiet agros.trial' >"$t/cmdline"
for d in "$t/boot" "$t/snap/boot"; do touch "$d/vmlinuz-linux-cachyos" "$d/initramfs-linux-cachyos.img" "$d/amd-ucode.img"; done
echo 'usr/lib/agros/boot-rollback' >"$t/image"
mkdir -p "$(dirname "$BOOT_TRIAL_ENV")"; grub-editenv "$BOOT_TRIAL_ENV" create; grub-editenv "$BOOT_TRIAL_ENV" set agros_desk=1
"$bt" arm "$t/snap" >/dev/null || fail "not armed"
[[ $(get agros_trial) == 2 && $(get agros_uuid) == 1234-abcd && $(get agros_root) == @ && $(get agros_snap) == @/.snapshots/5/snapshot &&
    $(get agros_kernel) == vmlinuz-linux-cachyos && $(get agros_initrds) == "amd-ucode.img initramfs-linux-cachyos.img" &&
    $(get agros_args) == "root=UUID=1234-abcd rw rootflags=defaults,subvol=/@ quiet panic=10" && -z $(get agros_desk) ]] ||
    fail "armed wrong: $(grub-editenv "$BOOT_TRIAL_ENV" list)"
# Not armed (and an older one cleared): GRUB's menu without the count; a login screen not AgrOS's; a snapshot whose boot
# image has no boot-rollback; a boot image missing from the snapshot
echo 'menu' >"$t/grub.cfg"
"$bt" arm "$t/snap" >/dev/null && fail "armed with GRUB's menu not counting"
[[ ! -e $BOOT_TRIAL_ENV ]] || fail "an older one left where this wasn't armed"
echo 'agros_trial' >"$t/grub.cfg"; echo 'command = "agreety --cmd hyprland-session"' >"$t/greetd.toml"
"$bt" arm "$t/snap" >/dev/null && fail "armed with a text login screen"
echo 'command = "/etc/greetd/caelestia-greeter/run"' >"$t/greetd.toml"; echo 'usr/lib/agros/snapshot-overlay' >"$t/image"
"$bt" arm "$t/snap" >/dev/null && fail "armed for a snapshot whose boot image has no boot-rollback"
echo 'usr/lib/agros/boot-rollback' >"$t/image"; rm "$t/snap/boot/amd-ucode.img"
"$bt" arm "$t/snap" >/dev/null && fail "armed for a snapshot without the microcode"
touch "$t/snap/boot/amd-ucode.img"
[[ ! -e $BOOT_TRIAL_ENV ]] || fail "a file left where it wasn't armed"

# pending (the shutdown's install waits on it): while the count runs or the desktop isn't confirmed; not when armed
# and not yet booted, nor with nothing armed
"$bt" arm "$t/snap" >/dev/null
"$bt" pending >/dev/null && fail "pending before a boot was counted"
for c in 1 0 greeter rollback; do
    grub-editenv "$BOOT_TRIAL_ENV" set "agros_trial=$c"
    "$bt" pending >/dev/null || fail "not pending at $c"
done
"$bt" disarm; "$bt" pending >/dev/null && fail "pending with nothing armed"

# A desktop already open when the login screen is looked for (it came and went between two looks): taken as up, the
# desktop watched, never restarted under it
armed 1
timeline "0=20 $me Hyprland" "3=20 $me Hyprland;21 $me qs -c caelestia"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls ]] || fail "an open desktop restarted for no login screen seen: $(cat "$t/calls" 2>/dev/null)"

# A boot GRUB didn't count (picked from the menu: no agros.trial): not watched, the count left
armed 1; timeline
sed -i 's/ agros.trial//' "$t/cmdline"
watch
[[ $(get agros_trial) == 1 && ! -e $t/calls ]] || fail "a boot GRUB didn't count watched"
echo 'BOOT_IMAGE=/@/boot/vmlinuz-linux-cachyos root=UUID=1234-abcd rw rootflags=subvol=@ quiet agros.trial' >"$t/cmdline"

# The login screen, then the desktop with Caelestia's shell: cleared, the rollback's note gone
armed 1; echo old >"$t/au/rolled-back"
timeline 0= "3=$greeter" "6=$greeter;20 $me Hyprland --watchdog-fd 4" "8=20 $me Hyprland;21 $me qs -c caelestia -n -d"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls && ! -e $t/au/rolled-back ]] || fail "the desktop up didn't clear it: $(cat "$t/calls" 2>/dev/null)"

# A session without its shell for 3 min: told, not restarted (its apps open), tried once more at the next restart;
# again: told, the count at 0 (the snapshot at the next restart)
armed 0
timeline "0=$greeter" "2=20 $me Hyprland"
watch
[[ $(cat "$t/calls") == "told The desktop didn't start properly after the update. Restart the PC to try again"* &&
    $(get agros_trial) == greeter && $(get agros_desk) == 1 ]] ||
    fail "a desktop without its shell not told: $(grub-editenv "$BOOT_TRIAL_ENV" list) $(cat "$t/calls" 2>/dev/null)"
timeline "0=20 $me Hyprland"
watch
[[ $(cat "$t/calls") == *"again. Restart the PC: the system from before the update comes back by itself" && $(get agros_trial) == 0 ]] ||
    fail "a desktop failing twice didn't set the count to 0: $(cat "$t/calls")"

# Sessions ending within seconds 3 times (Hyprland crashing at login, no session left open): restarted; but not the
# children a session starts, which carry its name a moment
armed greeter
timeline "0=20 bob Hyprland" 2= "3=21 bob Hyprland" 5= "6=22 bob Hyprland" 8=
watch
[[ $(cat "$t/calls" 2>/dev/null) == "systemctl reboot" && $(get agros_desk) == 1 ]] || fail "a desktop crashing at login not a failure"
armed greeter
timeline "0=20 bob Hyprland" "1=20 bob Hyprland;30:20 bob Hyprland" "2=20 bob Hyprland" "3=20 bob Hyprland;31:20 bob Hyprland" \
    "4=20 bob Hyprland" "5=20 bob Hyprland;32:20 bob Hyprland" "6=20 bob Hyprland;33 bob qs -c caelestia"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls ]] || fail "a session's children taken for sessions: $(cat "$t/calls" 2>/dev/null)"
# ...nor one session ended after a while (a log out) and the next coming up
armed greeter
timeline "0=20 bob Hyprland;21 bob qs -c caelestia" 15= "16=22 bob Hyprland;23 bob qs -c caelestia"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls ]] || fail "a log out taken as a failure"

# No login screen in 4 min: restarted, GRUB's count left as it is
armed 1
timeline
watch
[[ $(cat "$t/calls") == "systemctl reboot" && $(get agros_trial) == 1 && -z $(get agros_desk) && $(cat "$t/clock") -ge 119 ]] ||
    fail "no login screen not restarted: $(grub-editenv "$BOOT_TRIAL_ENV" list)"

# A failure that can't be written down (GRUB's file read-only): cleared, never restarted
armed greeter
chmod a-w "$BOOT_TRIAL_ENV" "$(dirname "$BOOT_TRIAL_ENV")"
timeline "0=20 bob Hyprland" 2= "3=21 bob Hyprland" 5= "6=22 bob Hyprland" 8=
if grub-editenv "$BOOT_TRIAL_ENV" set x=1 2>/dev/null; then
    skipped "GRUB's file still written read-only (root)"
else
    watch 2>/dev/null
    [[ ! -e $t/calls ]] || fail "restarted with the failure not written down"
fi
chmod u+w "$BOOT_TRIAL_ENV" "$(dirname "$BOOT_TRIAL_ENV")"

# The boot GRUB brought the snapshot back on: this boot's note (its boot id), cleared; no note, said to agros-check
echo 1111 >"$t/boot_id"
armed rollback
echo "2026-11-27 10:00 @/.snapshots/5/snapshot 1111 1" >"$t/au/rolled-back"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/au/rollback-failed ]] || fail "the snapshot brought back not cleared"
armed rollback
echo "2026-11-20 10:00 @/.snapshots/4/snapshot 2222 1" >"$t/au/rolled-back"
watch
[[ ! -e $BOOT_TRIAL_ENV && -s $t/au/rollback-failed ]] || fail "a rollback that didn't happen not noted"

# A snapshot booted from the menu (the root an overlay): nothing done
armed 1
stub findmnt 'case " $* " in *" FSTYPE "*) echo overlay ;; esac'
timeline; watch
[[ $(get agros_trial) == 1 && ! -e $t/calls ]] || fail "acted on a snapshot booted from the menu"
echo "ok boot-trial"
