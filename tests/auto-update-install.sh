#!/usr/bin/env bash
# system/auto-update-setup.sh's /usr/local/bin/auto-update, made from the setup script with its paths moved into a
# throwaway folder and pacman/snapper (and the boot half's curl, flatpak, sudo) stand-ins. The install at shutdown
# (--install): the safety snapshot taken without DBus (at shutdown snapperd can't be started over it), a failed install
# puts pacman's package lists back, and how it went is written down for dotfiles-check (ok, held for a new Qt, failed,
# nothing to install); nothing installed from a boot download that didn't finish or under another of pacman's users,
# counted without wiping a failed or held install, and said by dotfiles-check; the boot's lists taken by content or the
# mirror's time (not the time a copy gave them); one cut off has pacman's lists put back at the next boot. The generated
# script is shellchecked, and shutdown's own time limit is longer than the install's; the boot's download's unit holds off
# neither shutdown nor sleep
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/pac/sync" "$t/au/db/sync"
# The script as auto-update-setup.sh writes it (system/render.sh's render_auto_update: its heredoc, with $user, $home
# and dotfiles-check's lock holders filled in, as dotfiles-check renders it to compare with the installed one)
# shellcheck source=/dev/null  # (system/render.sh)
source "$here/system/render.sh"
[[ $(pacman_holders_of "$here") == *pacman*packagekitd* && -n $(lock_holder_of "$here") ]] ||
    fail "dotfiles-check's pacman_holders or lock_holder not found"
render_auto_update "$here" "$(id -un)" "$t/home" |
    sed -e "s|/var/lib/auto-update|$t/au|g" -e "s|/var/lib/pacman|$t/pac|g" -e "s|/var/log/auto-update.log|$t/log|g" \
        -e "s|for m in /boot |for m in $t/boot |" -e "s|/etc/grub.d/41_snapshots-btrfs|$t/grub-btrfs|g" \
        -e "s|command -v limine-snapper-sync|command -v $t/limine-sync|; s|^\( *\)limine-snapper-sync >|\1$t/limine-sync >|" \
        >"$t/auto-update"
grep -q -- '--install' "$t/auto-update" || fail "auto-update not found in the setup script"
# (the script itself checked: nothing else reads it before it runs at boot and shutdown)
bash -n "$t/auto-update" || fail "the generated auto-update doesn't parse"
if command -v shellcheck >/dev/null; then
    out=$(shellcheck -s bash "$t/auto-update") || fail "shellcheck on the generated auto-update: $out"
fi
# The boot's download (only that: the install is at shutdown) holds off neither power off nor sleep
unit=$(heredoc "$here/system/auto-update-setup.sh" /etc/systemd/system/auto-update.service)
[[ $(grep '^ExecStart=' <<<"$unit") == "ExecStart=/usr/local/bin/auto-update" ]] ||
    fail "auto-update.service doesn't start the download by itself: $(grep '^ExecStart=' <<<"$unit")"
grep -q 'systemd-inhibit' <<<"$unit" && fail "the boot's download blocks shutdown and sleep (systemd-inhibit)"
# Flatpaks from a file at boot: downloaded with nothing held, then reinstalled with sleep and power off held by root
# (logind refuses the user that hold outside a session) around that step alone
# shellcheck disable=SC2016  # (the generated script's own text)
{ grep -q -- '-H .*/flatpak-bundle-update" --fetch "$fetched"$' "$t/auto-update" &&
    ! grep -- '--fetch "$fetched"' "$t/auto-update" | grep -q systemd-inhibit &&
    grep -B2 -- '--install-fetched "$fetched"' "$t/auto-update" | grep -q '^ *timeout 30m systemd-inhibit --what=sleep:shutdown --mode=block '; } ||
    fail "the boot's Flatpak reinstall not held by root around that step alone: $(grep -n -A6 'Those from a file' "$t/auto-update")"
# Shutdown's own limit (the targets' JobTimeoutSec) longer than the install's (TimeoutStopSec), so it can't cut it off
stop=$(sed -n 's/^TimeoutStopSec=\([0-9]*\)min$/\1/p' "$here/system/auto-update-setup.sh")
job=$(grep -o 'JobTimeoutSec=[0-9]*min' "$here/system/auto-update-setup.sh" | grep -o '[0-9]*')
{ [[ -n $stop && -n $job ]] && ((job > stop)); } || fail "shutdown's limit ($job min) not longer than the install's ($stop min)"
# The install at shutdown after every user session (Hyprland, the shell, an Updates run's pacman): stopped in the
# reverse order, so before systemd-user-sessions (and the boot's download), after the network (still up for hooks)
# shellcheck source=/dev/null  # (system/render.sh)
source "$here/system/render.sh"
unit=$(heredoc "$here/system/auto-update-setup.sh" /etc/systemd/system/auto-update-install.service)
{ grep -qxE 'Before=.*\bsystemd-user-sessions\.service\b.*' <<<"$unit" && grep -qxE 'Before=.*\bauto-update\.service\b.*' <<<"$unit" &&
    grep -qxE 'After=.*\bnetwork\.target\b.*' <<<"$unit" &&
    # (nor on /boot's mount: before systemd-user-sessions, the login screen waited on a slow boot partition)
    ! grep -E '^(RequiresMountsFor|After|Requires)=' <<<"$unit" | grep -qE '/boot|boot\.mount'; } || fail "the install's unit not ordered after user sessions: $unit"
# pacman: -Qu says what's waiting ($QU, exit $QU_RC); -Su installs (exit $PACMAN_RC; $PACMAN_HANG: hangs, to be cut off);
# -Syuw the boot's download ($SYUW_RC)
cat >"$t/bin/pacman" <<EOF
#!/bin/sh
case \$1 in
    -Qu) [ -z "\$QU" ] || printf '%s\n' "\$QU"; exit \${QU_RC:-0} ;;
    -Q) [ -n "\$Q_HAVE" ] || exit 1; echo "\$2 \$Q_HAVE" ;;
    -Su) echo "pacman \$* (SNAP_PAC_SKIP=\$SNAP_PAC_SKIP)" >>"$t/calls"; echo "installing foo"
        # (the boot partition kept open by the install all along)
        ! ls -l /proc/\$PPID/fd 2>/dev/null | grep -q " $t/boot\$" || echo "boot held" >>"$t/calls"
        [ -z "\$PACMAN_HANG" ] || { echo \$\$ >"$t/hung"; exec sleep 60; }
        [ "\${PACMAN_RC:-0}" = 0 ] || echo "error: boom"; exit \${PACMAN_RC:-0} ;;
    -Syuw) echo "download \$*" >>"$t/calls"; exit \${SYUW_RC:-0} ;;
esac
EOF
# snapper at shutdown: over DBus it fails (snapperd can't start while the system goes down), and only what worked is noted
cat >"$t/bin/snapper" <<EOF
#!/bin/sh
case " \$* " in *" --no-dbus "*) echo "snapper \$*" >>"$t/calls" ;; *) exit 1 ;; esac
EOF
for s in curl flatpak sudo; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$s"; done
# fstab and mounts (this machine's not read): $FSTAB_BOOT puts /boot in fstab, $BOOT_UNMOUNTED has it not mounted
# shellcheck disable=SC2016  # (expanded by the stand-ins)
# (and what's mounted there: $BOOT_FSTYPE, autofs an automount's placeholder; the boot folder a throwaway one)
mkdir -p "$t/boot"
cat >"$t/bin/findmnt" <<EOF
#!/bin/sh
case "\$*" in
    "--fstab -n -o TARGET $t/boot") [ -z "\$FSTAB_BOOT" ] || echo "$t/boot" ;;
    *FSTYPE*"--mountpoint $t/boot") echo "\${BOOT_FSTYPE:-vfat}" ;;
esac
exit 0
EOF
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ -z "$BOOT_UNMOUNTED" ]\n' >"$t/bin/mountpoint"
# pgrep -x: something taking pacman's lock running ($HOLDER_RUNS: a process of its own, as lock_holder reads its command
# line); the rest: nothing. systemctl list-jobs: $JOBS
sleep 300 & holder=$!
trap 'kill $holder 2>/dev/null; rm -rf "$t"' EXIT
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$1" = -x ] && [ -n "$HOLDER_RUNS" ] && { echo %s; exit 0; }\nexit 1\n' "$holder" >"$t/bin/pgrep"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" != list-jobs ] || printf "%%s\n" "$JOBS"\nexit 0\n' >"$t/bin/systemctl"
chmod +x "$t/bin/"* "$t/auto-update"
export PATH=$t/bin:$PATH QU="foo 1-1 -> 2-1"
# pacman's list the one an earlier install put there (copied before cp -p: its time the copy's, now), the download's
# newer but with the mirror's time, earlier: still taken (by content, it's this one's own copy)
lists() {
    echo old >"$t/pac/sync/core.db"
    mkdir -p "$t/au/copied"; sha256sum <"$t/pac/sync/core.db" >"$t/au/copied/core.db.sum"
    echo new >"$t/au/db/sync/core.db"; touch -d '2 hours ago' "$t/au/db/sync/core.db"; touch "$t/au/db/complete"
}
res() { cat "$t/au/install-result" 2>/dev/null; }

lists
"$t/auto-update" --install || fail "the install failed: $(cat "$t/log")"
grep -q "^snapper.* create " "$t/calls" || fail "no safety snapshot taken: $(cat "$t/calls")"
grep -q "^pacman -Su" "$t/calls" || fail "nothing installed: $(cat "$t/calls")"
# (neither grub-btrfs nor Limine's snapper sync here: the boot menu's list left alone, quietly)
grep -q "boot menu" "$t/log" && fail "a missing boot menu tool said: $(cat "$t/log")"
grep -q "^pacman -Su .*(SNAP_PAC_SKIP=y)" "$t/calls" || fail "snap-pac's snapshots (failing over DBus at shutdown) not skipped: $(cat "$t/calls")"
[[ $(cat "$t/pac/sync/core.db") == new ]] || fail "the boot's package lists weren't used"
[[ $(res) == "ok "* ]] || fail "the install's result not written down: $(res)"
[[ ! -e $t/au/installing && ! -e $t/au/prev ]] || fail "an install that went fine left its marks"
grep -q "^installing foo" "$t/log" || fail "pacman's output not in the log"
# The snapshot into the boot menu's list right after it (grub-btrfsd, which would, is stopped at shutdown): by
# grub-btrfs's own script, else Limine's snapper sync
grep -q "command -v $t/limine-sync" "$t/auto-update" || fail "test setup: Limine's snapper sync not moved to the stand-in"
printf '#!/bin/sh\necho "grub-btrfs $*" >>%s/calls\n' "$t" >"$t/grub-btrfs"
printf '#!/bin/sh\necho "limine-sync $*" >>%s/calls\n' "$t" >"$t/limine-sync"
chmod +x "$t/grub-btrfs" "$t/limine-sync"
for menu in grub-btrfs limine-sync; do
    lists
    : >"$t/calls"
    "$t/auto-update" --install >/dev/null || fail "the install with $menu failed"
    [[ $(grep -v '^boot held' "$t/calls" | cut -d' ' -f1 | paste -sd' ') == "snapper snapper $menu pacman" ]] ||
        fail "the snapshot not put in the boot menu ($menu) right after it: $(cat "$t/calls")"
    rm -f "$t/grub-btrfs"
done
rm "$t/limine-sync"

# A failed install: pacman's lists back as they were (not newer than its packages), and written down with pacman's reason
lists
PACMAN_RC=1 "$t/auto-update" --install && fail "a failed install reported success"
[[ $(cat "$t/pac/sync/core.db") == old ]] || fail "pacman's package lists not put back after a failed install"
[[ $(res) == "failed "*"error: boom" ]] || fail "a failed install not written down: $(res)"

# A new Qt: held back (the lists back as they were), said as held
lists
QU=$'qt6-base 6.9.0-1 -> 6.10.0-1\nfoo 1-1 -> 2-1' "$t/auto-update" --install || fail "a held install failed"
[[ $(res) == "held "* && -s $t/au/held && $(cat "$t/pac/sync/core.db") == old ]] || fail "a new Qt not held back: $(res)"
# Nothing to install: ok (and no "held" left from before)
lists
QU='' QU_RC=1 "$t/auto-update" --install || fail "nothing to install failed"
[[ $(res) == "ok "* && ! -e $t/au/held ]] || fail "nothing to install not written down as ok: $(res)"
# pacman can't list the updates: failed, the lists back
lists
QU="error: failed to init transaction" QU_RC=1 "$t/auto-update" --install && fail "pacman's error reported success"
[[ $(res) == "failed "*"failed to init transaction" && $(cat "$t/pac/sync/core.db") == old ]] ||
    fail "pacman's error listing the updates not written down as failed: $(res)"

# The boot's download didn't finish (cut off, or failed), or something using pacman still runs: nothing installed,
# pacman's lists left alone, the shutdowns counted beside how the last install went (failed, held: still said)
echo "qt6-base 6.9.0-1 -> 6.10.0-1" >"$t/au/held"
before=$(res)
for n in 1 2 3; do
    lists
    # (the third: one holding pacman's lock; the lock alone, with nothing behind it, is no reason)
    if ((n == 3)); then export HOLDER_RUNS=1; : >"$t/pac/db.lck"; else rm "$t/au/db/complete"; fi
    : >"$t/calls"
    "$t/auto-update" --install || fail "an install with no finished download failed"
    [[ $(cat "$t/pac/sync/core.db") == old && ! -s $t/calls ]] || fail "installed (run $n) from a download that didn't finish, or under pacman: $(cat "$t/calls")"
    [[ $(cut -d' ' -f1 "$t/au/skipped") == "$n" ]] || fail "the shutdowns with nothing installed not counted: $(cat "$t/au/skipped")"
done
unset HOLDER_RUNS
rm "$t/pac/db.lck"
[[ $(res) == "$before" && -s $t/au/held ]] || fail "a skipped install wiped how the last one went: $(res)"
grep -q "something using pacman still ran ($holder sleep 300)" "$t/log" || fail "skipped for pacman's other user, not said"
[[ $(cut -d' ' -f3- "$t/au/skipped") == "something using pacman still ran"* ]] || fail "the skip's reason not written down: $(cat "$t/au/skipped")"
# dotfiles-check says it, and the failed install still
mkdir -p "$t/h"
for s in hyprctl Hyprland qs; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$s"; chmod +x "$t/bin/$s"; done
out=$(HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac "$here/.local/bin/dotfiles-check" 2>&1) || true  # (problems: exit 1)
[[ $out == *"hasn't installed for 3 shutdowns in a row"*"the last: something using pacman still ran"* &&
    $out == *"failed to install at shutdown"* && $out == *"held back"* ]] ||
    fail "dotfiles-check didn't say the skipped installs, or the failed or held one: $out"
# (the held Qt installed since, by Updates: not said any more, though only the next shutdown's install takes its file
# away; the old one still installed: said)
out=$(Q_HAVE=6.10.0-1 HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ -s $t/au/held && $out != *"held back"* ]] || fail "a held-back Qt said after it was installed: $out"
out=$(Q_HAVE=6.9.0-1 HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"held back"* ]] || fail "a held-back Qt said gone while the old one is still installed: $out"
# The boot partition in fstab but not mounted: nothing installed (a kernel would go to the folder under it), said
lists
: >"$t/calls"
FSTAB_BOOT=1 BOOT_UNMOUNTED=1 "$t/auto-update" --install || fail "an install with /boot not mounted failed"
[[ $(cat "$t/pac/sync/core.db") == old && ! -s $t/calls && $(cut -d' ' -f3- "$t/au/skipped") == "the boot partition ($t/boot) isn't mounted" ]] ||
    fail "installed with /boot not mounted, or not said: $(cat "$t/calls") $(cat "$t/au/skipped")"
FSTAB_BOOT=1 "$t/auto-update" --install >/dev/null || fail "an install with /boot mounted failed"
{ grep -q "^pacman -Su" "$t/calls" && grep -qx "boot held" "$t/calls"; } ||
    fail "nothing installed with /boot mounted, or /boot not kept busy through it: $(cat "$t/calls")"
# An automount's placeholder (autofs) still there after a look inside: not mounted, nothing installed
lists
: >"$t/calls"
FSTAB_BOOT=1 BOOT_FSTYPE=autofs "$t/auto-update" --install >/dev/null || fail "an install with /boot's automount unmounted failed"
[[ ! -s $t/calls && $(cut -d' ' -f3- "$t/au/skipped") == "the boot partition ($t/boot) isn't mounted" ]] ||
    fail "installed with only /boot's automount placeholder there: $(cat "$t/calls")"
# A soft reboot (the kernel keeps running): nothing installed, counted with its reason
lists
: >"$t/calls"
JOBS="  42 soft-reboot.target start waiting" "$t/auto-update" --install || fail "an install at a soft reboot failed"
[[ $(cat "$t/pac/sync/core.db") == old && ! -s $t/calls && $(cut -d' ' -f3- "$t/au/skipped") == "a soft reboot"* ]] ||
    fail "installed at a soft reboot, or not counted: $(cat "$t/calls") $(cat "$t/au/skipped")"
# A real install after them: the count gone, how it went written down
lists
QU='' QU_RC=1 "$t/auto-update" --install || fail "nothing to install failed"
[[ $(res) == "ok "* && ! -e $t/au/skipped && ! -e $t/au/held ]] || fail "a real install didn't replace the skipped ones: $(res)"
# pacman's lists synced since by the Updates app (the mirror's time, newer; not the copy this put there): left as they are
lists
echo updates-app >"$t/pac/sync/core.db"
QU='' QU_RC=1 "$t/auto-update" --install || fail "nothing to install failed"
[[ $(cat "$t/pac/sync/core.db") == updates-app ]] || fail "the Updates app's newer lists replaced by the boot's older ones"
# ...and the download marks itself finished only when it is
SYUW_RC=1 "$t/auto-update" || true
[[ ! -e $t/au/db/complete ]] || fail "a failed download marked as finished"
"$t/auto-update" || fail "the boot's download failed"
[[ -e $t/au/db/complete ]] || fail "a finished download not marked"

# An install cut off at shutdown (pacman killed mid-way): the next boot puts pacman's lists back, and its lock
lists
PACMAN_HANG=1 "$t/auto-update" --install &
pid=$!
for _ in {1..100}; do [[ -s $t/hung ]] && break; sleep 0.1; done
[[ -s $t/hung ]] || fail "the test's hanging install didn't start"
kill -9 "$pid" "$(cat "$t/hung")" 2>/dev/null; wait "$pid" 2>/dev/null || true
: >"$t/pac/db.lck"
[[ $(cat "$t/pac/sync/core.db") == new && -e $t/au/installing ]] || fail "test setup: the cut-off install's state"
[[ $(res) == "failed "*"cut off"* ]] || fail "a cut-off install not written down as failed: $(res)"
grep -q "^installing foo" "$t/log" || fail "a cut-off install's output not in the log"
"$t/auto-update" || fail "the boot after a cut-off install failed"
[[ $(cat "$t/pac/sync/core.db") == old && ! -e $t/au/installing && ! -e $t/pac/db.lck ]] ||
    fail "a cut-off install's lists or lock not put back at the next boot"
# Cut off again, and at the next boot something holds pacman's lock: put off (its lists and lock left), then done by
# the next install before anything else (its lock no longer in the way), which goes on to install
lists
PACMAN_HANG=1 "$t/auto-update" --install &
pid=$!
rm -f "$t/hung"; for _ in {1..100}; do [[ -s $t/hung ]] && break; sleep 0.1; done
kill -9 "$pid" "$(cat "$t/hung")" 2>/dev/null; wait "$pid" 2>/dev/null || true
: >"$t/pac/db.lck"
HOLDER_RUNS=1 "$t/auto-update" || fail "the boot with the recovery put off failed"
[[ $(cat "$t/pac/sync/core.db") == new && -e $t/au/installing && -e $t/pac/db.lck ]] ||
    fail "the recovery not put off while something held pacman's lock"
grep -q "recovered later" "$t/log" || fail "the put-off recovery not said"
: >"$t/calls"; : >"$t/log"
"$t/auto-update" --install || fail "the install after a put-off recovery failed: $(cat "$t/log")"
{ grep -q "the last install was cut off" "$t/log" && grep -q "removing the lock it left" "$t/log"; } ||
    fail "the install didn't recover the cut-off one first: $(cat "$t/log")"
[[ $(res) == "ok "* && $(cat "$t/pac/sync/core.db") == new && ! -e $t/au/installing && ! -e $t/pac/db.lck ]] ||
    fail "the install after the recovery didn't go through: $(res)"
grep -q "^pacman -Su" "$t/calls" || fail "nothing installed after the recovery"
# A lock an Updates run's pacman left (killed at shutdown; not one of this install's), nothing having it open: stale,
# taken out and said, and the install goes on. One something still has open: left, nothing installed
lists
: >"$t/pac/db.lck"; : >"$t/calls"; : >"$t/log"
"$t/auto-update" --install || fail "the install with a stale lock failed"
{ [[ ! -e $t/pac/db.lck ]] && grep -q "removing a stale lock" "$t/log" && grep -q "^pacman -Su" "$t/calls"; } ||
    fail "a stale pacman lock not taken out before the install: $(cat "$t/log")"
lists
: >"$t/pac/db.lck"; : >"$t/calls"
sleep 300 3<"$t/pac/db.lck" & opener=$!
: >"$t/log"; "$t/auto-update" --install || fail "the install with pacman's lock open failed"; out=$(cat "$t/log")
kill $opener; wait $opener 2>/dev/null || true
[[ -e $t/pac/db.lck && ! -s $t/calls && $out == *"something has pacman's lock open"* ]] ||
    fail "pacman's lock taken out (or installed) while something had it open: $out / $(cat "$t/calls")"
rm -f "$t/pac/db.lck"
echo "ok auto-update-install"
