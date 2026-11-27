#!/usr/bin/env bash
# boot-trial (agros-boot): armed after an update with the snapshot's kernel, boot image and options (GRUB's file: real
# grub-editenv); not armed where GRUB's menu doesn't count or the snapshot can't boot itself. Each boot: a count GRUB
# didn't take one off cleared; the login screen up stops the count; the desktop up clears it; a desktop failing
# restarts the PC, its second failure sets the count to 0; a login screen that never comes up restarts it; the boot
# GRUB brought the snapshot back on says whether it came. And GRUB's menu script (01_agros-trial) is valid GRUB script
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
    BOOT_TRIAL_BOOT_ID=$t/boot_id AUTO_UPDATE_DIR=$t/au BOOT_TRIAL_POLL=0
mkdir -p "$t/au" "$t/snap/boot" "$t/snap/usr/lib/agros"
get() { grub-editenv "$BOOT_TRIAL_ENV" list | sed -n "s/^$1=//p"; }
# Stand-ins: btrfs (the snapshot's path from the top), findmnt (the root's UUID, a Btrfs root), systemctl (the restart,
# noted), sleep (the clock: one tick a look) and ps (the processes at that tick: the last $t/ps.<tick> file at or before
# it, "<pid> <user> <command line>" a line, in the two forms boot-trial asks for)
stub btrfs 'echo "@/.snapshots/5/snapshot"'
stub findmnt 'case " $* " in *" UUID "*) echo 1234-abcd ;; *" FSTYPE "*) echo btrfs ;; esac'
stub systemctl "echo \"systemctl \$*\" >>$t/calls"
stub sleep "echo \$((\$(cat $t/clock 2>/dev/null || echo 0) + 1)) >$t/clock"
stub ps "n=\$(cat $t/clock 2>/dev/null || echo 0); f=; for ((k = 0; k <= n; k++)); do [[ -f $t/ps.\$k ]] && f=$t/ps.\$k; done
[[ -n \$f ]] || exit 0
case \$* in *comm=*) awk '{ print \$1, \$2, \$3 }' \"\$f\" ;; *) cut -d' ' -f2- \"\$f\" ;; esac"
export PATH=$t/bin:$PATH
# timeline <tick>=<processes, ";" between two> ...
timeline() { rm -f "$t"/ps.* "$t/clock" "$t/calls"; local a; for a; do tr ';' '\n' <<<"${a#*=}" >"$t/ps.${a%%=*}"; done; }
greeter='9 greeter qs -p /etc/greetd/caelestia-greeter'
# watch: boot-trial's, ended (the desktop's watch has no time limit: one that never decides fails here, not hangs)
watch() { local rc=0; timeout 20 "$bt" watch >/dev/null || rc=$?; ((rc != 124)) || fail "the watch never decided"; }

# Armed: the snapshot's kernel and boot image, this boot's options (BOOT_IMAGE out, agros.rollback in), the count at 2
echo 'set agros_trial' >"$t/grub.cfg"
echo 'BOOT_IMAGE=/@/boot/vmlinuz-linux-cachyos root=UUID=1234-abcd rw rootflags=subvol=@ quiet' >"$t/cmdline"
touch "$t/snap/boot/vmlinuz-linux-cachyos" "$t/snap/boot/initramfs-linux-cachyos.img" "$t/snap/usr/lib/agros/boot-rollback"
"$bt" arm "$t/snap" >/dev/null || fail "not armed"
[[ $(get agros_trial) == 2 && $(get agros_uuid) == 1234-abcd && $(get agros_linux) == /@/.snapshots/5/snapshot/boot/vmlinuz-linux-cachyos &&
    $(get agros_initrd) == /@/.snapshots/5/snapshot/boot/initramfs-linux-cachyos.img &&
    $(get agros_args) == "root=UUID=1234-abcd rw rootflags=subvol=@ quiet agros.rollback=@/.snapshots/5/snapshot" ]] ||
    fail "armed wrong: $(grub-editenv "$BOOT_TRIAL_ENV" list)"
# Not armed: GRUB's menu without the count; a snapshot whose boot image has no boot-rollback
rm -f "$BOOT_TRIAL_ENV"
echo 'menu' >"$t/grub.cfg"
"$bt" arm "$t/snap" >/dev/null && fail "armed with GRUB's menu not counting"
echo 'agros_trial' >"$t/grub.cfg"; rm "$t/snap/usr/lib/agros/boot-rollback"
"$bt" arm "$t/snap" >/dev/null && fail "armed for a snapshot without boot-rollback"
[[ ! -e $BOOT_TRIAL_ENV ]] || fail "a file left where it wasn't armed"
touch "$t/snap/usr/lib/agros/boot-rollback"

# A count GRUB didn't take one off (2 at boot): cleared, nothing else
"$bt" arm "$t/snap" >/dev/null; timeline
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls ]] || fail "a count GRUB didn't take one off acted on"

# The login screen, then the desktop with Caelestia's shell: cleared, the rollback's note gone
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=1; echo old >"$t/au/rolled-back"
timeline 0= "3=$greeter" "6=$greeter;20 alice Hyprland --watchdog-fd 4" "8=20 alice Hyprland;21 alice qs -c caelestia -n -d"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls && ! -e $t/au/rolled-back ]] || fail "the desktop up didn't clear it: $(cat "$t/calls" 2>/dev/null)"

# The login screen up, then the desktop without its shell for 3 min: restarted, tried once more; again: the count at 0
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=0
timeline "0=$greeter" "2=20 alice Hyprland"
watch
[[ $(cat "$t/calls") == "systemctl reboot" && $(get agros_trial) == greeter && $(get agros_desk) == 1 ]] ||
    fail "a desktop without its shell not tried again: $(grub-editenv "$BOOT_TRIAL_ENV" list) $(cat "$t/calls" 2>/dev/null)"
timeline "0=20 alice Hyprland"
watch
[[ $(cat "$t/calls") == "systemctl reboot" && $(get agros_trial) == 0 ]] || fail "a desktop failing twice didn't set the count to 0"

# Sessions ending within seconds 3 times (Hyprland crashing at login): a failure
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=greeter
timeline "0=20 bob Hyprland" 2= "3=21 bob Hyprland" 5= "6=22 bob Hyprland" 8=
watch
[[ $(cat "$t/calls" 2>/dev/null) == "systemctl reboot" && $(get agros_desk) == 1 ]] || fail "a desktop crashing at login not a failure"
# ...but one session ended after a while (a log out) and the next coming up: fine
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=greeter
timeline "0=20 bob Hyprland;21 bob qs -c caelestia" 15= "16=22 bob Hyprland;23 bob qs -c caelestia"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/calls ]] || fail "a log out taken as a failure"

# No login screen in 4 min: restarted, GRUB's count left as it is
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=1
timeline
watch
[[ $(cat "$t/calls") == "systemctl reboot" && $(get agros_trial) == 1 && -z $(get agros_desk) && $(cat "$t/clock") -ge 119 ]] ||
    fail "no login screen not restarted: $(grub-editenv "$BOOT_TRIAL_ENV" list)"

# The boot GRUB brought the snapshot back on: this boot's note (its boot id), cleared; no note, said to agros-check
echo 1111 >"$t/boot_id"
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=rollback
echo "2026-11-27 10:00 @/.snapshots/5/snapshot 1111 1" >"$t/au/rolled-back"
watch
[[ ! -e $BOOT_TRIAL_ENV && ! -e $t/au/rollback-failed ]] || fail "the snapshot brought back not cleared"
"$bt" arm "$t/snap" >/dev/null; grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=rollback
echo "2026-11-20 10:00 @/.snapshots/4/snapshot 2222 1" >"$t/au/rolled-back"
watch
[[ ! -e $BOOT_TRIAL_ENV && -s $t/au/rollback-failed ]] || fail "a rollback that didn't happen not noted"

# A snapshot booted from the menu (the root an overlay): nothing done
stub findmnt 'case " $* " in *" FSTYPE "*) echo overlay ;; esac'
mkdir -p "$(dirname "$BOOT_TRIAL_ENV")" && grub-editenv "$BOOT_TRIAL_ENV" create && grub-editenv "$BOOT_TRIAL_ENV" set agros_trial=1
timeline; watch
[[ $(get agros_trial) == 1 && ! -e $t/calls ]] || fail "acted on a snapshot booted from the menu"
echo "ok boot-trial"
