#!/usr/bin/env bash
# agros-system's auto-update (packages/agros-system/auto-update), with its paths moved into a
# throwaway folder and pacman/snapper (and the boot half's curl, flatpak, sudo) stand-ins. The install at shutdown
# (--install): the safety snapshot taken without DBus (at shutdown snapperd can't be started over it), a failed install
# puts pacman's package lists back, and how it went is written down for dotfiles-check (ok, held for a new Qt, failed,
# nothing to install); nothing installed from a boot download that didn't finish or under another of pacman's users,
# counted without wiping a failed or held install, and said by dotfiles-check; the boot's lists taken by content or the
# mirror's time (not the time a copy gave them); one cut off has pacman's lists put back at the next boot. The generated
# script is shellchecked, and shutdown's own time limit is longer than the install's; the boot's download's unit holds off
# neither shutdown nor sleep
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# (the batteries battery-low reads: none, but where a test makes them; never this machine's own)
export AGROS_POWER_SUPPLY=$t/ps
mkdir -p "$t/bin" "$t/pac/sync" "$t/au/db/sync"
# The script as agros-system installs it (agros-scripts' helpers, pacman-lock-holder and wait-online, from here)
au=$here/packages/agros-system
# (the AgrOS users: just this one. --as: mktemp and rm run, update-kinds and flatpak-bundle-update noted, not run (they'd
# update this machine's own); update-kinds hands $KINDS_NOTE back on fd 3, flatpak-bundle-update --fetch finds
# something with $FETCHED. --notify and --notify-wait noted; --notify-wait tells someone, but with $NOBODY)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/bash\ncalls=%s/calls\n%s\n' "$t" 'case $1 in
    --list) id -un; [ -z "${TWO_USERS:-}" ] || id -un ;;
    --as) shift 2; echo "as $*" >>"$calls"; while [ "$1" = --fd ]; do shift 2; done
        [ -z "${TWO_USERS:-}" ] || ! IFS= read -r -t 1 line || echo "stdin $line" >>"$calls"
        case "$*" in
            mktemp* | "rm -rf -- "*) exec "$@" ;;
            *update-kinds*) [ -z "${KINDS_NOTE:-}" ] || printf "%s\n" "$KINDS_NOTE" >&3 ;;
            *--fetch*) [ -z "${FETCHED:-}" ] || echo app >"${@: -1}/fetched" ;;
        esac ;;
    --notify) shift; echo "notify-later $*" >>"$calls"; [ -z "${TWO_USERS:-}" ] || ! IFS= read -r -t 1 line || echo "stdin $line" >>"$calls" ;;
    --notify-wait) shift; echo "notify $*" >>"$calls"; [ -z "${NOBODY:-}" ] ;;
esac' >"$t/bin/agros-each-user"
chmod +x "$t/bin/agros-each-user"
sed -e "s|/var/lib/auto-update|$t/au|g" -e "s|/var/lib/pacman|$t/pac|g" -e "s|/var/log/auto-update.log|$t/log|g" \
    -e "s|for m in /boot |for m in $t/boot |" -e "s|/etc/grub.d/41_snapshots-btrfs|$t/grub-btrfs|g" \
    -e "s|command -v limine-snapper-sync|command -v $t/limine-sync|; s|^\( *\)limine-snapper-sync >|\1$t/limine-sync >|" \
    -e "s|\${AGROS_EACH_USER:-/usr/lib/agros/bin/agros-each-user}|$t/bin/agros-each-user|" \
    -e "s|/usr/lib/agros/auto-update-aur|$t/auto-update-aur|g; s|/usr/lib/agros/auto-update |$t/auto-update |g" \
    -e "s|/usr/lib/agros/bin/|$here/.local/bin/|g" \
    -e "s|/var/lib/agros/|$t/agros/|g" -e "s|/usr/share/pacman/keyrings/agros.gpg|$t/agros.gpg|g" \
    "$au/auto-update" >"$t/auto-update"
sed -e "s|/var/lib/auto-update|$t/au|g" -e "s|/usr/lib/agros/auto-update-aur|$t/auto-update-aur|g" \
    -e "s|/usr/lib/agros/bin/|$here/.local/bin/|g" "$au/auto-update-aur" >"$t/auto-update-aur"
grep -q -- '--install' "$t/auto-update" || fail "auto-update has no --install"
# (the script itself checked: nothing else reads it before it runs at boot and shutdown)
bash -n "$t/auto-update" || fail "the generated auto-update doesn't parse"
if command -v shellcheck >/dev/null; then
    out=$(shellcheck -s bash "$t/auto-update") || fail "shellcheck on the generated auto-update: $out"
fi
# The upstream gate failing, at boot as at shutdown: pacman.conf as it is (its Include holds Hyprland), never the copy an
# earlier run made for older lists (a newer Hyprland, not checked yet, let through)
gates=$(grep '/update-gate ' "$au/auto-update")
[[ $(wc -l <<<"$gates") == 2 && $(grep -c '|| cp /etc/pacman.conf "$gated"$' <<<"$gates") == 2 ]] ||
    fail "a run through the upstream gate without its fallback: $gates"
# The boot's download (only that: the install is at shutdown) holds off neither power off nor sleep
unit=$(cat "$au/auto-update.service")
[[ $(grep '^ExecStart=' <<<"$unit") == "ExecStart=/usr/lib/agros/auto-update" ]] ||
    fail "auto-update.service doesn't start the download by itself: $(grep '^ExecStart=' <<<"$unit")"
grep -q 'systemd-inhibit' <<<"$unit" && fail "the boot's download blocks shutdown and sleep (systemd-inhibit)"
# Flatpaks from a file at boot: downloaded with nothing held, then reinstalled with sleep and power off held by root
# (logind refuses the user that hold outside a session) around that step alone, under its own half hour; the
# system-wide ones once as root, each user's as them, through the same steps
# shellcheck disable=SC2016  # (the generated script's own text)
{ grep -q -- '"$@" '"$here"'/.local/bin/flatpak-bundle-update --fetch "$fetched"$' "$t/auto-update" &&
    ! grep -q systemd-inhibit <<<"$(grep -- '--fetch "$fetched"' "$t/auto-update")" &&
    grep -q '^ *timeout 30m systemd-inhibit --what=sleep:shutdown --mode=block ' <<<"$(grep -B2 -- '--install-fetched "$fetched"' "$t/auto-update")" &&
    grep -qx 'bundles' "$t/auto-update" && grep -qx '    bundles "$each_user" --as "$user"' "$t/auto-update" &&
    grep -qx '    "$@" rm -rf -- "$fetched"' "$t/auto-update" &&
    # (on disk: the file and the repo it's read into, in /tmp, took memory)
    grep -qx '    fetched=$("$@" mktemp -d -p /var/tmp agros-flatpak.XXXXXX) || return 0' "$t/auto-update" &&
    [[ $(grep -v '^ *#' "$t/auto-update" | grep -c 'flatpak-bundle-update') == 4 ]]; } ||
    fail "the boot's Flatpak reinstall not held by root around that step alone (root's and each user's): $(grep -n -A14 '^bundles() {' "$t/auto-update")"
# Shutdown's own limit (the targets' JobTimeoutSec) longer than the install's (TimeoutStopSec), so it can't cut it off
stop=$(sed -n 's/^TimeoutStopSec=\([0-9]*\)min$/\1/p' "$au/auto-update-install.service")
job=$(grep -o 'JobTimeoutSec=[0-9]*min' "$au/auto-update-timeout.conf" | grep -o '[0-9]*')
{ [[ -n $stop && -n $job ]] && ((job > stop)); } || fail "shutdown's limit ($job min) not longer than the install's ($stop min)"
# The install at shutdown after every user session (Hyprland, the shell, an Updates run's pacman): stopped in the
# reverse order, so before systemd-user-sessions (and the boot's download), after the network (still up for hooks)
unit=$(cat "$au/auto-update-install.service")
{ grep -qxE 'Before=.*\bsystemd-user-sessions\.service\b.*' <<<"$unit" && grep -qxE 'Before=.*\bauto-update\.service\b.*' <<<"$unit" &&
    grep -qxE 'After=.*\bnetwork\.target\b.*' <<<"$unit" &&
    # (nor on /boot's mount: before systemd-user-sessions, the login screen waited on a slow boot partition)
    ! grep -qE '/boot|boot\.mount' <<<"$(grep -E '^(RequiresMountsFor|After|Requires)=' <<<"$unit")"; } || fail "the install's unit not ordered after user sessions: $unit"
# ...and before udisks2 and the system bus stop (fwupd finds the EFI partition through udisks2)
{ grep -qxE 'After=.*\budisks2\.service\b.*' <<<"$unit" && grep -qxE 'After=.*\bdbus\.service\b.*' <<<"$unit" &&
    grep -qx 'Wants=udisks2.service' <<<"$unit"; } || fail "the install's unit not ordered before udisks2 stops: $unit"
# pacman: -Qu says what's waiting ($QU, exit $QU_RC; $QU_ERR on stderr); -Su installs (exit $PACMAN_RC; $PACMAN_HANG: hangs, to be cut off);
# -Sy the boot's lists ($SY_ERR: fails, saying it), -Suw its download ($SYUW_RC; $SUW_ERR: fails, saying it), -Sw the
# keyrings' download first and -S their install first (exit $KEYRING_RC); -Si the version a package would update to ($SI_NEW)
cat >"$t/bin/pacman" <<EOF
#!/bin/sh
case \$1 in
    -Qu) [ -z "\$QU" ] || printf '%s\n' "\$QU"; [ -z "\$QU_ERR" ] || echo "\$QU_ERR" >&2; exit \${QU_RC:-0} ;;
    -Q) [ -n "\$Q_HAVE" ] || exit 1; echo "\$2 \$Q_HAVE" ;;
    -Su) echo "pacman \$* (SNAP_PAC_SKIP=\$SNAP_PAC_SKIP)" >>"$t/calls"; echo "installing foo"
        # (the boot partition kept open by the install all along)
        fds=\$(ls -l /proc/\$PPID/fd 2>/dev/null); case "\$fds" in *" $t/boot"*) echo "boot held" >>"$t/calls" ;; esac
        [ -z "\$PACMAN_HANG" ] || { echo \$\$ >"$t/hung"; exec sleep 60; }
        case " \$* " in *" agros-aur/"*) [ -z "\$PACMAN_AUR_RC" ] || { echo "error: failed to commit transaction (conflicting files)"; exit 1; } ;; esac
        [ "\${PACMAN_RC:-0}" = 0 ] || echo "error: boom"; exit \${PACMAN_RC:-0} ;;
    -Sy) [ -z "\$SY_ERR" ] || { echo "\$SY_ERR" >&2; exit 1; }; exit 0 ;;
    -Sw) echo "keyrings-download \$*" >>"$t/calls" ;;
    -S) echo "pacman \$* (SNAP_PAC_SKIP=\$SNAP_PAC_SKIP)" >>"$t/calls"; exit \${KEYRING_RC:-0} ;;
    -Si) [ -z "\$SI_NEW" ] || echo "Version         : \$SI_NEW"; exit 0 ;;
    -Suw) echo "download \$*" >>"$t/calls"; [ -e "$t/au/downloading" ] && echo "download marked" >>"$t/calls"
        [ -z "\$SUW_ERR" ] || { echo "\$SUW_ERR" >&2; exit 1; }
        exit \${SYUW_RC:-0} ;;
    # (\$SUW_BREAKS: a library's update breaking the held hyprland, until it's held too: pacman's dry run says so)
    -Sup) if [ -n "\$SUW_BREAKS" ] && ! grep -q "IgnorePkg = libfoo" "\$3"; then
            echo "error: failed to prepare transaction (could not satisfy dependencies)"
            echo ":: installing libfoo (2-1) breaks dependency 'libfoo.so=1-64' required by hyprland"; exit 1
        fi ;;
esac
EOF
# snapper at shutdown: over DBus it fails (snapperd can't start while the system goes down), and only what worked is noted
cat >"$t/bin/snapper" <<EOF
#!/bin/sh
case " \$* " in *" --no-dbus "*) echo "snapper \$*" >>"$t/calls" ;; *) exit 1 ;; esac
EOF
for s in curl flatpak; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$s"; done
# (through PAM, never: a logind session for the user)
for s in sudo runuser su; do printf '#!/bin/sh\necho "PAM %s" >>%s/calls\nexit 1\n' "$s" "$t" >"$t/bin/$s"; done
# shellcheck disable=SC2016
printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin/systemd-inhibit"
# fwupd: nothing waiting ($FW: get-updates' JSON); fwupdtool, the shutdown's, noted (exit $FWTOOL_RC; $FW_LEFT: what
# it still offers after, a device it skipped, saying why; $FW_NOROOM: the EFI partition too small); systemd-run noted
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$1" = get-updates ] && [ -n "$FW" ] && { echo "$FW"; exit 0; }\nexit 2\n' >"$t/bin/fwupdmgr"
# shellcheck disable=SC2016
printf '#!/bin/sh\nif [ "$1" = get-updates ]; then [ -n "$FW_LEFT" ] && echo "$FW_LEFT"; exit 0; fi\necho "fwupdtool $*" >>%s/calls\necho "flashing"\n[ -z "$FW_LEFT" ] || echo "  ‣ Device requires AC power to be connected"\n[ -z "$FW_NOROOM" ] || echo "/boot does not have sufficient space, required 64.0 MB, need additional 30.0 MB"\nexit ${FWTOOL_RC:-0}\n' "$t" >"$t/bin/fwupdtool"
printf '#!/bin/sh\necho "systemd-run $*" >>%s/calls\n' "$t" >"$t/bin/systemd-run"
# fstab and mounts (this machine's not read): $FSTAB_BOOT puts /boot in fstab, $BOOT_UNMOUNTED has it not mounted
# shellcheck disable=SC2016  # (expanded by the stand-ins)
# (and what's mounted there: $BOOT_FSTYPE, autofs an automount's placeholder; the boot folder a throwaway one)
mkdir -p "$t/boot"
cat >"$t/bin/findmnt" <<EOF
#!/bin/sh
case "\$*" in
    "--fstab -n -o TARGET $t/boot") [ -z "\$FSTAB_BOOT" ] || echo "$t/boot" ;;
    *FSTYPE*"--mountpoint $t/boot") echo "\${BOOT_FSTYPE:-vfat}" ;;
    # (the root's: \$ROOT_FSTYPE, overlay a booted snapshot's)
    "-no FSTYPE /") echo "\${ROOT_FSTYPE:-btrfs}" ;;
esac
exit 0
EOF
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ -z "$BOOT_UNMOUNTED" ]\n' >"$t/bin/mountpoint"
# pgrep -x: something taking pacman's lock running ($HOLDER_RUNS: a process of its own, as lock_holder reads its command
# line); the rest: nothing. systemctl list-jobs: $JOBS
# (a pacman on these lists: its --dbpath the test's, as pacman-lock-holder reads it)
printf '#!/bin/sh\nsleep 300\n' >"$t/holder"; chmod +x "$t/holder"
"$t/holder" --dbpath "$t/pac" 2>/dev/null & holder=$!
disown "$holder"  # (killed at the end without a job notice after "ok")
on_exit 'pkill -P $holder; kill $holder'
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$1" = -x ] && [ -n "$HOLDER_RUNS" ] && { echo %s; exit 0; }\nexit 1\n' "$holder" >"$t/bin/pgrep"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" != list-jobs ] || printf "%%s\n" "$JOBS"\nexit 0\n' >"$t/bin/systemctl"
chmod +x "$t/bin/"* "$t/auto-update" "$t/auto-update-aur"
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
# A new Python (minor version) the same: held, its line alone in "held"; a Python bugfix release holds nothing
lists
QU=$'python 3.13.7-1 -> 3.14.0-1\nfoo 1-1 -> 2-1' "$t/auto-update" --install >/dev/null || fail "a held install failed"
[[ $(res) == "held "*"a new python"* && $(cat "$t/au/held") == "python 3.13.7-1 -> 3.14.0-1" ]] || fail "a new Python not held back: $(res)"
lists
QU=$'python 3.14.0-1 -> 3.14.1-1\nfoo 1-1 -> 2-1' "$t/auto-update" --install >/dev/null || fail "an install with a Python bugfix failed"
[[ $(res) == "ok "* ]] || fail "a Python bugfix release held the update back: $(res)"
# Nothing to install: ok (and no "held" left from before)
lists
QU='' QU_RC=1 "$t/auto-update" --install || fail "nothing to install failed"
[[ $(res) == "ok "* && ! -e $t/au/held ]] || fail "nothing to install not written down as ok: $(res)"
# Only what pacman.conf holds back (IgnorePkg's "[ignored]"): nothing to install (no snapshot, no pacman -Su), and an
# ignored new Qt holds nothing back
lists
: >"$t/calls"
QU='foo 1-1 -> 2-1 [ignored]' "$t/auto-update" --install || fail "only ignored updates failed"
[[ $(res) == "ok "* && ! -s $t/calls ]] || fail "ignored updates counted as waiting: $(res) $(cat "$t/calls")"
lists
: >"$t/calls"
QU=$'qt6-base 6.9.0-1 -> 6.10.0-1 [ignored]\nfoo 1-1 -> 2-1' "$t/auto-update" --install >/dev/null || fail "an install beside an ignored Qt failed"
[[ $(res) == "ok "* ]] && grep -q '^pacman -Su' "$t/calls" || fail "an ignored new Qt held the update back: $(res)"
# Nothing to install, with a warning on stderr: still ok, not a failure
lists
QU='' QU_ERR="warning: config file /etc/pacman.conf, line 9: directive 'X' not recognized" QU_RC=1 "$t/auto-update" --install ||
    fail "nothing to install with a warning failed"
[[ $(res) == "ok "* ]] || fail "a warning from pacman -Qu written down as a failure: $(res)"
# pacman can't list the updates: failed, the lists back
lists
QU_ERR="error: failed to init transaction" QU_RC=1 "$t/auto-update" --install && fail "pacman's error reported success"
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
grep -q "something using pacman still ran ($holder /bin/sh $t/holder --dbpath $t/pac)" "$t/log" || fail "skipped for pacman's other user, not said"
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
# Nearly empty on battery (a laptop off its charger): nothing installed, counted with its reason; on its charger, or
# with more charge (a mouse's own battery, nearly empty, isn't the computer's), installed. (battery-low's folder: $t/ps)
battery() {  # <name> <capacity> <status> [<scope>]
    mkdir -p "$t/ps/$1"
    echo Battery >"$t/ps/$1/type"; echo "$2" >"$t/ps/$1/capacity"; echo "$3" >"$t/ps/$1/status"
    [[ -z ${4:-} ]] || echo "$4" >"$t/ps/$1/scope"
}
battery BAT0 9 Discharging
lists; : >"$t/calls"
"$t/auto-update" --install || fail "an install on a nearly empty battery failed"
[[ $(cat "$t/pac/sync/core.db") == old && ! -s $t/calls && $(cut -d' ' -f3- "$t/au/skipped") == "on battery, nearly empty (9 percent)"* ]] ||
    fail "installed on a nearly empty battery, or not counted: $(cat "$t/calls") $(cat "$t/au/skipped")"
for b in "BAT0 9 Charging" "BAT0 80 Discharging"; do
    rm -rf "$t/ps"
    # shellcheck disable=SC2086  # (its name, capacity and status: one word each)
    battery $b
    battery hidpp_battery_0 5 Discharging Device
    lists; : >"$t/calls"
    "$t/auto-update" --install >/dev/null || fail "an install with the battery $b failed"
    grep -q '^pacman -Su' "$t/calls" || fail "nothing installed with the battery $b (and a mouse's nearly empty): $(cat "$t/au/skipped")"
done
rm -rf "$t/ps"
# pacman's lists kept aside, whole and on disk (sync), before the first is replaced and the install marked; one that
# can't be kept (a full disk): nothing replaced, nothing installed, counted
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\necho "$* installing=$([ -e %s/au/installing ] && echo yes || echo no) list=$(cat %s/pac/sync/core.db) kept=$(cat %s/au/prev/core.db 2>/dev/null)" >%s/synced\n' \
    "$t" "$t" "$t" "$t" >"$t/bin/sync"
# shellcheck disable=SC2016
printf '#!/bin/sh\nfor a; do last=$a; done\n[ -z "$CP_FAIL_PREV" ] || [ "$last" != %s/au/prev/ ] || exit 1\nexec %s "$@"\n' \
    "$t" "$(command -v cp)" >"$t/bin/cp"
chmod +x "$t/bin/sync" "$t/bin/cp"
lists; : >"$t/calls"
"$t/auto-update" --install >/dev/null || fail "an install failed: $(tail -5 "$t/log")"
[[ $(cat "$t/synced" 2>/dev/null) == "-f $t/au/prev $t/pac/sync installing=no list=old kept=old" ]] ||
    fail "pacman's lists not kept aside and on disk before they're replaced and the install marked: $(cat "$t/synced" 2>/dev/null)"
lists; : >"$t/calls"
CP_FAIL_PREV=1 "$t/auto-update" --install || fail "an install whose lists couldn't be kept aside failed"
[[ $(cat "$t/pac/sync/core.db") == old && ! -e $t/au/installing && ! -s $t/calls &&
    $(cut -d' ' -f3- "$t/au/skipped") == "pacman's package lists couldn't be kept aside"* ]] ||
    fail "pacman's lists replaced (or installed) with no copy kept aside: $(cat "$t/calls") $(cat "$t/au/skipped")"
rm "$t/bin/sync" "$t/bin/cp"
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
# The keyrings first: downloaded alone before the rest (one pacman.conf holds back left out), so a package signed by a
# key the keyring here hasn't got (or has expired) failing the rest's download leaves them; installed first at shutdown,
# on their own when the rest didn't download (the lists put back after), said with the boot's error from pacman
sig="error: failed to commit transaction (invalid or corrupted package (PGP signature))"
: >"$t/calls"
QU=$'archlinux-keyring 20261001-1 -> 20261115-1
cachyos-keyring 1-1 -> 2-1 [ignored]
foo 1-1 -> 2-1' SUW_ERR=$sig     "$t/auto-update" || fail "the boot with the download failing on a key failed"
[[ $(grep -E '^(keyrings-)?download -S' "$t/calls" | cut -d' ' -f1 | paste -sd' ') == "keyrings-download download" ]] &&
    grep -qE '^keyrings-download -Sw .* -- archlinux-keyring$' "$t/calls" ||
    fail "the keyrings not downloaded alone before the rest (nor only the one not held back): $(cat "$t/calls")"
[[ $(cat "$t/au/db/keyrings" 2>/dev/null) == archlinux-keyring && ! -e $t/au/db/complete &&
    $(cat "$t/au/download-failed" 2>/dev/null) == "$sig" ]] ||
    fail "the keyrings downloaded, or the download's error, not written down: $(cat "$t/au/db/keyrings" "$t/au/download-failed" 2>&1)"
grep -qF "$sig" "$t/log" || fail "the download's error not in the log"
lists; rm "$t/au/db/complete"; rm -f "$t/au/skipped"; : >"$t/calls"
"$t/auto-update" --install || fail "the install of the keyrings alone failed: $(tail -5 "$t/log")"
[[ $(cat "$t/calls") == "pacman -S --needed --noconfirm --config $t/au/prev/gated.conf -- archlinux-keyring (SNAP_PAC_SKIP=y)" &&
    $(cat "$t/pac/sync/core.db") == old && ! -e $t/au/installing ]] ||
    fail "the keyrings not installed alone (the lists put back) with the rest not downloaded: $(cat "$t/calls")"
[[ $(cut -d' ' -f3- "$t/au/skipped") == "the boot's download didn't finish ($sig): the keyrings installed first, archlinux-keyring" ]] ||
    fail "the unfinished download not said with pacman's error and the keyrings: $(cat "$t/au/skipped")"
# (with the rest downloaded: the keyrings first, then the rest)
lists; : >"$t/calls"
"$t/auto-update" --install >/dev/null || fail "the install with the keyrings first failed"
[[ $(grep '^pacman' "$t/calls" | cut -d' ' -f1-2 | paste -sd' ') == "pacman -S pacman -Su" && $(res) == "ok "* ]] ||
    fail "the keyrings not installed before the rest: $(cat "$t/calls")"
# A download that failed with no keyrings to take: nothing installed, said with pacman's error
SY_ERR="error: failed to synchronize all databases" "$t/auto-update" || fail "the boot whose lists failed failed"
[[ ! -e $t/au/db/keyrings && $(cat "$t/au/download-failed" 2>/dev/null) == "error: failed to synchronize all databases" ]] ||
    fail "the failed sync's error not written down, or the last keyrings kept"
lists; rm "$t/au/db/complete"; : >"$t/calls"
"$t/auto-update" --install || fail "the install after a failed sync failed"
[[ ! -s $t/calls && $(cut -d' ' -f3- "$t/au/skipped") == "the boot's download didn't finish (error: failed to synchronize all databases)" ]] ||
    fail "installed after a failed sync, or not said with its error: $(cat "$t/calls") $(cat "$t/au/skipped")"
# ...and a download that finished: its error and keyrings gone
"$t/auto-update" || fail "the boot's download failed"
[[ -e $t/au/db/complete && ! -e $t/au/download-failed && ! -e $t/au/db/keyrings ]] || fail "a finished download kept the last one's error or keyrings"
# Through the upstream gate (update-gate, the real one): a new Hyprland not yet checked by AgrOS's CI held (its pacman.conf
# kept with the gate's Include, used for the download and the shutdown's install), said; once approved, let through
printf '%s\n' '[options]' "Include = $t/agros-gate.conf" '' '[agros]' 'Server = https://agros.invalid/x86_64' >"$t/base.conf"
# (curl: the approved list, $APPROVED, when set, else as unreachable; anything else as before, online)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/sh\ncase " $* " in *agros-approved*) ;; *) exit 0 ;; esac\n[ -n "$APPROVED" ] || exit 7\nwhile [ "$1" != -o ]; do shift; done\nprintf "%%s\\n" "$APPROVED" >"$2"\n' >"$t/bin/curl"
echo 'IgnorePkg = hyprland' >"$t/agros-gate.conf"
sed "s|update-gate /etc/pacman.conf|update-gate $t/base.conf|" "$t/auto-update" >"$t/auto-update-gate"; chmod +x "$t/auto-update-gate"
grep -q "update-gate $t/base.conf" "$t/auto-update-gate" || fail "test setup: the gate's base pacman.conf not set"
export AGROS_GATE=$t/agros-gate.conf AGROS_GATE_CACHE=$t/approved
: >"$t/calls"; : >"$t/log"
out=$(Q_HAVE=0.57.2-1 SI_NEW=0.58.0-1 "$t/auto-update-gate" 2>&1) || fail "the boot with Hyprland held failed: $out"
out=$(cat "$t/log")
{ [[ $out == *"waits for AgrOS's check: hyprland 0.57.2-1 -> 0.58.0-1"* ]] && grep -qF "Include = $t/agros-gate.conf" "$t/au/pacman.conf" &&
    grep -qF "download -Suw --noconfirm --config $t/au/pacman.conf --dbpath" "$t/calls" && [[ -e $t/au/db/complete ]]; } ||
    fail "a Hyprland not checked yet not held at the download, or not said: $out / $(cat "$t/calls")"
# (the shutdown decides again, on the lists it installs from: its pending list and its install through that pacman.conf)
lists
QU="foo 1-1 -> 2-1" Q_HAVE=0.57.2-1 SI_NEW=0.58.0-1 "$t/auto-update-gate" --install >/dev/null || fail "the install after a held download failed"
grep -qF -- "--config $t/au/prev/gated.conf" <<<"$(grep '^pacman -Su' "$t/calls")" &&
    [[ $(sed -n '/--install =====/,$p' "$t/log") == *"waits for AgrOS's check: hyprland 0.57.2-1 -> 0.58.0-1"* ]] ||
    fail "the shutdown's install not through the gate: $(cat "$t/calls") / $(tail -5 "$t/log")"
# (approved meanwhile, after the boot's download held it: still held at shutdown, from the list kept then (offline), not
# the whole set downloaded at shutdown)
lists; : >"$t/log"
APPROVED='hyprland 0.58.0' QU="foo 1-1 -> 2-1" Q_HAVE=0.57.2-1 SI_NEW=0.58.0-1 "$t/auto-update-gate" --install >/dev/null || fail "the install, approved since the boot, failed"
[[ $(cat "$t/log") == *"waits for AgrOS's check: hyprland 0.57.2-1 -> 0.58.0-1"* ]] ||
    fail "a Hyprland approved after the boot's download let through at shutdown: $(tail -5 "$t/log")"
echo 'hyprland 0.58.0' >"$t/approved"
: >"$t/log"
out=$(Q_HAVE=0.57.2-1 SI_NEW=0.58.0-2 "$t/auto-update-gate" 2>&1) || fail "the boot with Hyprland approved failed: $out"
out=$(cat "$t/log")
[[ $out != *"waits for"* ]] && ! grep -q "agros-gate" "$t/au/pacman.conf" || fail "an approved Hyprland held: $out / $(cat "$t/au/pacman.conf")"
# ...and a newer one, not checked yet, in lists synced since (the Updates app): held at shutdown, not let through by the
# boot's decision
lists
QU="foo 1-1 -> 2-1" Q_HAVE=0.57.2-1 SI_NEW=0.58.1-1 "$t/auto-update-gate" --install >/dev/null || fail "the install with a newer Hyprland failed"
[[ $(sed -n '/--install =====/,$p' "$t/log" | tail -4) == *"waits for AgrOS's check: hyprland 0.57.2-1 -> 0.58.1-1"* ]] ||
    fail "a Hyprland newer than the boot's approved one let through at shutdown: $(tail -5 "$t/log")"
# ...held, with a library's update breaking it (its new soname): that library held with it, the download done
rm -f "$t/approved"
out=$(Q_HAVE=0.57.2-1 SI_NEW=0.58.0-1 SUW_BREAKS=1 "$t/auto-update-gate" 2>&1) || fail "the boot with a held library failed: $out"
out=$(cat "$t/log")
[[ $out == *"libfoo (held with hyprland: its update would break it)"* && -e $t/au/db/complete ]] && grep -qx 'IgnorePkg = libfoo' "$t/au/pacman.conf" ||
    fail "a library breaking the held Hyprland not held too: $out / $(cat "$t/au/pacman.conf")"
export AGROS_GATE=$t/no-gate  # (the rest: no gate, as lib.sh leaves it)
: >"$t/calls"
"$t/auto-update" || fail "the boot's download failed"
[[ -e $t/au/db/complete ]] || fail "a finished download not marked"
# (marked downloading while it runs, for Updates' update-apps to wait on: from the start of the run, gone once it's
# done, not through the Flatpaks and the rest)
grep -qx "download marked" "$t/calls" && [[ ! -e $t/au/downloading ]] || fail "the download not marked while it ran, or the mark left: $(cat "$t/calls")"
grep -q '^touch "\$au/downloading"$' <<<"$(sed -n '/^# The last shutdown.s install cut off before it finished/,$p' "$t/auto-update" | head -1; grep -B4 '^# The last shutdown.s install cut off before it finished' "$t/auto-update")" ||
    fail "the mark not made first thing at boot"
grep -q '^PAM' "$t/calls" && fail "a user's part run through PAM: $(grep '^PAM' "$t/calls")"
# (fd 3, its notes, handed on by name: agros-each-user gives a user's command no other descriptor of root's)
grep -q '^as --fd 3 env XDG_RUNTIME_DIR=.*/update-kinds --boot ' "$t/calls" || fail "the users' kinds not run as them (agros-each-user --as --fd 3): $(cat "$t/calls")"
# A new Proton (update-kinds' notice, on fd 3): said on that user's desktop once they're logged in, by its own unit
: >"$t/calls"
KINDS_NOTE=$'steam\tNew Proton: GE-Proton11-12\tRestart Steam' "$t/auto-update" || fail "the boot with a Proton notice failed"
grep -qx "notify-later --user $(id -un) -a Updates -i steam New Proton: GE-Proton11-12 Restart Steam" "$t/calls" ||
    fail "the Proton notice not handed to agros-each-user --notify: $(cat "$t/calls")"
# Each user's commands not reading the list of users (their stdin elsewhere): two users, both run
: >"$t/calls"; : >"$t/log"
TWO_USERS=1 FETCHED=1 KINDS_NOTE=$'steam\tNew Proton: GE-Proton11-12\tRestart Steam' "$t/auto-update" </dev/null || fail "the boot with two users failed"
[[ $(grep -c "^-- $(id -un)$" "$t/log") == 2 && $(grep -c 'update-kinds --boot' "$t/calls") == 2 ]] && ! grep -q '^stdin' "$t/calls" ||
    fail "a user's command read the list of users: $(grep '^stdin' "$t/calls") $(grep -c "^-- " "$t/log")"
# Flatpaks from a file: reinstalled as the user under root's hold; not with too little of the run's 4 h left
: >"$t/calls"
FETCHED=1 "$t/auto-update" || fail "the boot with Flatpaks from a file failed"
grep -q '^as .*flatpak-bundle-update --install-fetched' "$t/calls" || fail "the Flatpaks from a file not reinstalled: $(cat "$t/calls")"
sed 's/((SECONDS > 4 \* 3600 - 35 \* 60))/((1))/' "$t/auto-update" >"$t/auto-update-late"; chmod +x "$t/auto-update-late"
grep -q '((1))' "$t/auto-update-late" || fail "test setup: the time left not made short"
: >"$t/calls"; : >"$t/log"
FETCHED=1 "$t/auto-update-late" || true
! grep -q -- '--install-fetched' "$t/calls" && grep -q "too little of the run's time left" "$t/log" ||
    fail "the Flatpaks from a file reinstalled with too little time left: $(cat "$t/calls")"
# Root's own pass (the system-wide Flatpaks): its helper run as root itself (not through --as), the reinstall under the
# hold as the users' is (the helper and the hold noted, in a copy of the script)
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\necho "fbu $*" >>%s/calls\n[ "$1" != --fetch ] || [ -z "${FETCHED:-}" ] || echo app >"$2/fetched"\n[ "$1" != --no-origin-urls ] || [ -z "${NO_EMPTY:-}" ]\n' "$t" >"$t/bin/fbu"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho held >>%s/calls\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' "$t" >"$t/bin/hold-noted"
chmod +x "$t/bin/fbu" "$t/bin/hold-noted"
sed -e "s|$here/.local/bin/flatpak-bundle-update|$t/bin/fbu|g" -e "s|systemd-inhibit --what=sleep:shutdown|$t/bin/hold-noted --what=sleep:shutdown|" \
    "$t/auto-update" >"$t/auto-update-root"
chmod +x "$t/auto-update-root"
: >"$t/calls"
# (and root's flatpak update after its apps from a file had their -origin remotes' URLs emptied, flatpak noted)
cp "$t/bin/flatpak" "$t/flatpak-quiet"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" != update ] || echo "flatpak $*" >>%s/calls\n' "$t" >"$t/bin/flatpak"
FETCHED=1 "$t/auto-update-root" || fail "the boot with system-wide Flatpaks from a file failed"
root=$(grep -E '^(fbu|held|flatpak)' "$t/calls" | sed -n '1,5{s| /[^ ]*$||;p}')
[[ $root == $'fbu --no-origin-urls system user\nflatpak update -y --noninteractive\nfbu --fetch\nheld\nfbu --install-fetched' ]] ||
    fail "the system-wide Flatpaks not updated after their -origin URLs were emptied, then fetched and reinstalled by root under the hold: $(cat "$t/calls")"
# ...an -origin remote's URL that couldn't be emptied: no flatpak update, said
: >"$t/calls"; : >"$t/log"
NO_EMPTY=1 "$t/auto-update-root" || fail "the boot with an -origin remote's URL left failed"
! grep -q '^flatpak update' "$t/calls" && grep -q 'Flatpaks not updated: an app installed from a file kept the URL' "$t/log" ||
    fail "Flatpaks updated with an -origin remote's URL left: $(cat "$t/calls")"
mv -f "$t/flatpak-quiet" "$t/bin/flatpak"

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
sleep 300 3<"$t/pac/db.lck" 2>/dev/null & opener=$!
disown "$opener"
: >"$t/log"; "$t/auto-update" --install || fail "the install with pacman's lock open failed"; out=$(cat "$t/log")
kill $opener
[[ -e $t/pac/db.lck && ! -s $t/calls && $out == *"something has pacman's lock open"* ]] ||
    fail "pacman's lock taken out (or installed) while something had it open: $out / $(cat "$t/calls")"
rm -f "$t/pac/db.lck"

# The boot's AUR builds (auto-update-aur's, in $t/au/aur): installed in the same pacman transaction as the repo's, from
# their own repo (agros-aur, its list put in pacman's for the install alone), each rebuilt for the new Qt
aurdir=$t/au/aur
built() {
    rm -rf "$aurdir"; mkdir -p "$aurdir/repo"
    echo db >"$aurdir/repo/agros-aur.db"
    echo "quickshell-git 0.3-1" >"$aurdir/built"; echo quickshell-git >"$aurdir/rebuild"
    echo "qt6-base 6.10.0-1 " >"$aurdir/runtime-target"; touch "$aurdir/planned"
}
newqt=$'qt6-base 6.9.0-1 -> 6.10.0-1\nfoo 1-1 -> 2-1'
lists; built; : >"$t/calls"
QU=$newqt Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null || fail "the install with the AUR's rebuilds failed: $(tail -5 "$t/log")"
grep -q "^pacman -Su --noconfirm --config $t/au/prev/pacman.conf agros-aur/quickshell-git" "$t/calls" ||
    fail "the AUR's rebuild not in the repo's transaction: $(cat "$t/calls")"
[[ $(res) == "ok "* && ! -e $t/pac/sync/agros-aur.db ]] || fail "the AUR repo's list left in pacman's, or not ok: $(res)"
[[ $(cat "$t/au/qt-built") == "qt6-base 0.3 qt6-declarative 0.3 " ]] || fail "the Qt the shells were rebuilt for not written down: $(cat "$t/au/qt-built" 2>/dev/null)"
# (an AUR build no newer than what's installed, and no new Qt: not reinstalled)
lists; built; : >"$t/calls"
Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null || fail "the install beside an AUR build already installed failed"
grep -q 'agros-aur/' "$t/calls" && fail "an AUR build reinstalled with nothing new: $(cat "$t/calls")"
# A new Qt and a failed rebuild for it: the whole update waits (said, the lists back)
lists; built; rm "$aurdir/built"; echo "quickshell-git: its build failed" >"$aurdir/failed"; : >"$t/calls"
QU=$newqt Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null || fail "the held install failed"
[[ $(res) == "held "*"build failed"* && ! -s $t/calls && $(cat "$t/pac/sync/core.db") == old ]] ||
    fail "a new Qt installed without the shells rebuilt: $(res) $(cat "$t/calls")"
# ...or rebuilt older than what's installed (pacman would leave it, and the new Qt go in alone): waits too
lists; built; : >"$t/calls"
QU=$newqt Q_HAVE=0.4-1 "$t/auto-update" --install >/dev/null || fail "the held install failed"
[[ $(res) == "held "*"came out older than what's installed: quickshell-git" && ! -s $t/calls ]] ||
    fail "a new Qt installed with its rebuild older than what's installed: $(res) $(cat "$t/calls")"
# ...or rebuilt for another Qt than these lists bring: waits too
lists; built; echo "qt6-base 6.11.0-1 " >"$aurdir/runtime-target"; : >"$t/calls"
QU=$newqt Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null
[[ $(res) == "held "* && ! -s $t/calls ]] || fail "installed with the shells rebuilt for another Qt: $(res)"
# A new Qt with nothing built on it to rebuild: installed (and nothing built: no complaint of a missing list)
lists; built; : >"$aurdir/rebuild"; rm "$aurdir/built"; : >"$t/calls"; : >"$t/log"
QU=$newqt Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null
[[ $(res) == "ok "* ]] && grep -q '^pacman -Su' "$t/calls" || fail "a new Qt held back with nothing to rebuild: $(res)"
grep -q 'No such file' "$t/log" && fail "the install complains of a list the builds didn't write: $(grep 'No such file' "$t/log")"
# A new Qt, its rebuild built, an unrelated AUR app's build failed: installed with the rebuild, not held for the other
lists; built; echo "equibop: its build failed" >"$aurdir/failed"; : >"$t/calls"
QU=$newqt Q_HAVE=0.3-1 "$t/auto-update" --install >/dev/null
[[ $(res) == "ok "* ]] && grep -q '^pacman -Su .* agros-aur/quickshell-git' "$t/calls" ||
    fail "a new Qt held back for an unrelated AUR app's failed build: $(res) $(cat "$t/calls")"
# AUR apps pacman can't install (a file conflict): the rest installed without them, said; not when a new runtime needs
# them (failed, the lists back)
lists; built; : >"$aurdir/rebuild"; : >"$t/calls"
Q_HAVE=0.2-1 PACMAN_AUR_RC=1 "$t/auto-update" --install >/dev/null || fail "the install without the AUR apps failed: $(tail -5 "$t/log")"
[[ $(res) == "ok "* && $(grep -c '^pacman -Su' "$t/calls") == 2 ]] && grep -q "^pacman -Su --noconfirm --config $t/au/prev/pacman.conf --ignore quickshell-git (" "$t/calls" ||
    fail "the repo's part not installed without the AUR apps pacman refused: $(res) $(cat "$t/calls")"
[[ $(sed -n 2p "$t/au/aur-install-failed") == "quickshell-git 0.3-1" && $(head -1 "$t/au/aur-install-failed") == *"conflicting files"* ]] ||
    fail "the AUR apps left out not written down: $(cat "$t/au/aur-install-failed" 2>/dev/null)"
out=$(HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac Q_HAVE=0.2-1 "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"couldn't install AUR apps at shutdown (quickshell-git"*"conflicting files"* ]] || fail "dotfiles-check didn't say the AUR apps left out: $out"
lists; built; : >"$t/calls"
QU=$newqt Q_HAVE=0.3-1 PACMAN_AUR_RC=1 "$t/auto-update" --install >/dev/null && fail "a new Qt installed without its rebuild"
[[ $(res) == "failed "* && $(grep -c '^pacman -Su' "$t/calls") == 1 && $(cat "$t/pac/sync/core.db") == old ]] ||
    fail "a new Qt's rebuild refused, and the rest tried without it: $(res) $(cat "$t/calls")"
# (an install of them that goes through: the note gone)
lists; built; : >"$aurdir/rebuild"
Q_HAVE=0.2-1 "$t/auto-update" --install >/dev/null
[[ ! -e $t/au/aur-install-failed ]] || fail "the AUR apps' install failure still noted once they're installed"
# An AUR update that failed, no new Qt: the rest (the repo's, the AUR apps built) without it
lists; built; echo "equibop: the build failed" >"$aurdir/failed"; echo "equibop 1.1-1" >"$aurdir/wanted"; : >"$t/calls"
Q_HAVE=0.2-1 "$t/auto-update" --install >/dev/null
[[ $(res) == "ok "* ]] && grep -q '^pacman -Su .* agros-aur/quickshell-git' "$t/calls" ||
    fail "the rest not installed beside a failed AUR build: $(res) $(cat "$t/calls")"
grep -q "AUR apps wait" "$t/log" || fail "the AUR apps waiting not said"
out=$(HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"couldn't build AUR apps (equibop: the build failed): still waiting: equibop;"* ]] || fail "dotfiles-check didn't say the failed AUR build: $out"
rm -rf "$aurdir"

# Firmware: found at boot (fwupd), written down and said (in a unit of its own); installed at shutdown only once said,
# before the packages
FW='{"Devices":[{"DeviceId":"abc123","Name":"System Firmware","Version":"1.0","Releases":[{"Version":"1.2"}]}]}'
: >"$t/calls"
FW=$FW "$t/auto-update" || fail "the boot with firmware waiting failed"
[[ $(cat "$t/au/firmware") == $'abc123\tSystem Firmware\t1.0\t1.2' ]] || fail "the firmware waiting not written down: $(cat "$t/au/firmware" 2>/dev/null)"
grep -q "^systemd-run .*--unit=agros-firmware-note $t/auto-update --firmware-note" "$t/calls" || fail "the firmware not said: $(cat "$t/calls")"
lists; : >"$t/calls"
"$t/auto-update" --install >/dev/null
grep -q fwupdtool "$t/calls" && fail "firmware installed before the users were told"
# (said on the users' desktops once someone's logged in: agros-each-user --notify-wait; nobody yet: not marked told)
NOBODY=1 "$t/auto-update" --firmware-note
[[ ! -e $t/au/firmware-told ]] || fail "the firmware marked told with nobody told"
"$t/auto-update" --firmware-note
# (to every desktop, an account that isn't an administrator too: Updates offers that one no Update all)
grep -qx "notify .*Firmware update ready System Firmware: installed when you shut down or restart (an administrator can install it now from Updates)" "$t/calls" ||
    fail "the firmware not said on the desktop, for every account: $(cat "$t/calls")"
cmp -s "$t/au/firmware" "$t/au/firmware-told" || fail "the firmware said not marked told"
: >"$t/calls"
"$t/auto-update" --install >/dev/null
[[ $(head -1 "$t/calls") == "fwupdtool update --assume-yes --no-reboot-check abc123" ]] && grep -q '^pacman -Su' "$t/calls" ||
    fail "the firmware said not installed first at shutdown: $(cat "$t/calls")"
# (never under a time limit of its own: one cut a flash off midway)
grep -E 'timeout [^|]*fwupdtool update' "$t/auto-update" && fail "the firmware's flash under a time limit of its own"
[[ ! -e $t/au/firmware && ! -e $t/au/firmware-told ]] || fail "installed firmware still waiting"
grep -q "a UEFI or BIOS update applies at the next boot" "$t/log" || fail "a staged UEFI update not said"
# Skipped (fwupd's own checks: it needs AC power), though fwupdtool exits 0: the device still offers it after. Kept for
# the next shutdown, said by dotfiles-check with fwupd's reason; one that fails outright the same
FW=$FW "$t/auto-update"; cp "$t/au/firmware" "$t/au/firmware-told"
lists; : >"$t/log"; FW_LEFT=$FW "$t/auto-update" --install >/dev/null
[[ -s $t/au/firmware-told && -s $t/au/firmware-failed ]] || fail "a skipped firmware update (exit 0) not kept and noted"
grep -q "firmware: installed" "$t/log" && fail "a skipped firmware update logged as installed"
out=$(HOME=$t/h AUTO_UPDATE_DIR=$t/au PACMAN_DB_DIR=$t/pac "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"firmware update failed to install at shutdown"*"Device requires AC power to be connected"* ]] || fail "dotfiles-check didn't say the skipped firmware: $out"
lists; rm "$t/au/firmware-failed"; FWTOOL_RC=1 "$t/auto-update" --install >/dev/null
[[ -s $t/au/firmware-told && $(cut -d' ' -f3- "$t/au/firmware-failed") == flashing ]] || fail "a failed firmware update not kept and noted"
# The EFI partition too small for it (beside Windows, often Windows' 100 MB one): fwupd refuses it before writing
# anything, every time. Said once, at the next boot's login, as that; not tried again at every shutdown, nor said at
# every login (dotfiles-check), until a newer one comes
lists; : >"$t/calls"; FWTOOL_RC=1 FW_NOROOM=1 "$t/auto-update" --install >/dev/null
[[ ! -e $t/au/firmware-failed && ! -e $t/au/firmware-told ]] && cmp -s "$t/au/firmware" "$t/au/firmware-noroom" ||
    fail "a firmware update the EFI partition has no room for kept to try again, or said at every login"
lists; : >"$t/calls"; "$t/auto-update" --install >/dev/null
grep -q fwupdtool "$t/calls" && fail "a firmware update with no room for it tried again at the next shutdown"
FW=$FW "$t/auto-update"
grep -q -- "--firmware-note" "$t/calls" || fail "a firmware update with no room for it not said at the next boot"
"$t/auto-update" --firmware-note
grep -q "^notify .*Firmware update can't be installed System Firmware: the boot partition (EFI) is too small for it" "$t/calls" ||
    fail "a firmware update with no room for it not said as that: $(cat "$t/calls")"
lists; : >"$t/calls"; "$t/auto-update" --install >/dev/null; FW=$FW "$t/auto-update"
grep -qE "fwupdtool|--firmware-note" "$t/calls" && fail "a firmware update with no room for it tried or said again: $(cat "$t/calls")"
# (a newer one: said and tried as any)
: >"$t/calls"; FW=${FW/1.2/1.3} "$t/auto-update"; "$t/auto-update" --firmware-note
grep -q "^notify .*Firmware update ready System Firmware" "$t/calls" || fail "a newer firmware update not said: $(cat "$t/calls")"
lists; : >"$t/calls"; "$t/auto-update" --install >/dev/null
grep -q fwupdtool "$t/calls" || fail "a newer firmware update not tried, after one with no room: $(cat "$t/calls")"
# (with another device's beside it: which has no room isn't known, and the other may have been skipped for a reason of
# its own (AC power), so both fail as any: kept, tried again, the failure said)
FW2='{"Devices":[{"DeviceId":"abc123","Name":"System Firmware","Version":"1.0","Releases":[{"Version":"1.2"}]},
 {"DeviceId":"def456","Name":"Dock","Version":"2.0","Releases":[{"Version":"2.1"}]}]}'
FW=$FW2 "$t/auto-update"; cp "$t/au/firmware" "$t/au/firmware-told"
lists; : >"$t/calls"; FWTOOL_RC=1 FW_NOROOM=1 "$t/auto-update" --install >/dev/null
[[ $(wc -l <"$t/au/firmware-told") == 2 && -s $t/au/firmware-failed && ! -e $t/au/firmware-noroom ]] ||
    fail "two firmware updates, one with no room, both put off as having no room"
rm -f "$t/au/firmware-failed"
FW=$FW "$t/auto-update"; cp "$t/au/firmware" "$t/au/firmware-told"
# Too little of the install's time left: firmware not started; after a firmware update that took long, the packages put
# off to the next shutdown (counted)
sed 's/((SECONDS <= stop - packages - 25 \* 60))/((0))/' "$t/auto-update" >"$t/auto-update-late"; chmod +x "$t/auto-update-late"
grep -q '((0))' "$t/auto-update-late" || fail "test setup: the firmware's time left not made short"
lists; rm -f "$t/au/firmware-failed" "$t/au/skipped"; : >"$t/calls"; "$t/auto-update-late" --install >/dev/null
! grep -q fwupdtool "$t/calls" && grep -q '^pacman -Su' "$t/calls" || fail "firmware started with too little time left: $(cat "$t/calls")"
sed 's/((SECONDS <= stop - packages))/((0))/' "$t/auto-update" >"$t/auto-update-late"
grep -q '((0))' "$t/auto-update-late" || fail "test setup: the packages' time left not made short"
lists; : >"$t/calls"; "$t/auto-update-late" --install >/dev/null
grep -q fwupdtool "$t/calls" && ! grep -q '^pacman -Su' "$t/calls" && grep -q "firmware update took long" "$t/au/skipped" ||
    fail "the packages installed with too little time left after the firmware: $(cat "$t/calls")"
# Nothing waiting at the next boot: the notes gone, its failure too
"$t/auto-update"
[[ ! -e $t/au/firmware && ! -e $t/au/firmware-told && ! -e $t/au/firmware-failed && ! -e $t/au/firmware-noroom ]] ||
    fail "firmware no longer waiting still noted"

# The log keeps the last 20 runs
for _ in {1..25}; do "$t/auto-update" --install >/dev/null; done
n=$(grep -c '^===== .* --install =====$' "$t/log")
((n >= 19 && n <= 21)) || fail "the log not trimmed to its last runs: $n"
# ...root's and the admins' alone (every account's update output in it), one made before closed too
chmod 644 "$t/log"
"$t/auto-update" --install >/dev/null
[[ $(stat -c %a "$t/log") == 640 ]] || fail "the log open to every account: $(stat -c %a "$t/log")"

# A booted snapshot (its root an overlay in RAM), or the live USB: neither the boot's download nor the shutdown's
# install (all of it gone at the next boot), said in the log
for run in "" --install; do
    lists; : >"$t/calls"; : >"$t/log"
    ROOT_FSTYPE=overlay QU="foo 1-1 -> 2-1" "$t/auto-update" $run >/dev/null || fail "a booted snapshot's run ($run) failed"
    [[ ! -s $t/calls && ! -e $t/au/downloading ]] && grep -q "runs from a snapshot (or the live USB)" "$t/log" ||
        fail "a booted snapshot's run ($run) updated, or didn't say why not: $(cat "$t/calls") / $(cat "$t/log")"
done

# The day AgrOS's checks last passed (agros-arch-ok, beside the [agros] repo): taken only with a good signature by
# AgrOS's key beside it (a key of the test's own, where the script reads agros-keyring's); one with none, or by
# another key, as if that server didn't answer, said, the next one tried; none good, the copy kept as it was
export GNUPGHOME=$t/gnupg
mkdir -m700 "$GNUPGHOME"
for k in agros other; do
    gpg --batch --quiet --passphrase '' --quick-gen-key "$k <$k@agros.invalid>" ed25519 sign never >/dev/null 2>&1
done
gpg --batch --export agros@agros.invalid >"$t/agros.gpg" 2>/dev/null
[[ -s $t/agros.gpg ]] || fail "test setup: no key made"
# shellcheck disable=SC2016  # (expanded by the stand-ins)
printf '#!/bin/sh\n[ "$*" = "--repo agros Server" ] && printf "%%s\n" https://one.invalid/x86_64 https://two.invalid/x86_64\nexit 0\n' >"$t/bin/pacman-conf"
# (curl: each server's day, one.invalid's 2026/11/10, two.invalid's 2026/11/12, its .sig as $SIG_ONE / $SIG_TWO say:
# good (the default), none (a 404), other (by another key); anything else as before)
# shellcheck disable=SC2016
cat >"$t/bin/curl" <<'C'
#!/bin/bash
url=${*: -1}
case $url in *agros-arch-ok*) ;; *) exit 0 ;; esac
case $url in https://one.invalid/*) day=2026/11/10 sig=${SIG_ONE:-good} ;; *) day=2026/11/12 sig=${SIG_TWO:-good} ;; esac
while [[ $1 != -o ]]; do shift; done
[[ $url == *.sig ]] || { printf '%s\n' "$day" >"$2"; exit 0; }
case $sig in
    none) exit 22 ;;
    other) printf '%s\n' "$day" | gpg --batch --yes -u other@agros.invalid --detach-sign -o "$2" 2>/dev/null ;;
    *) printf '%s\n' "$day" | gpg --batch --yes -u agros@agros.invalid --detach-sign -o "$2" 2>/dev/null ;;
esac
C
chmod +x "$t/bin/pacman-conf" "$t/bin/curl"
: >"$t/log"; "$t/auto-update"
[[ $(cat "$t/agros/agros-arch-ok" 2>/dev/null) == 2026/11/10 ]] || fail "a well signed agros-arch-ok not taken: $(cat "$t/agros/agros-arch-ok" 2>&1)"
for bad in none other; do
    : >"$t/log"; SIG_ONE=$bad "$t/auto-update"
    [[ $(cat "$t/agros/agros-arch-ok") == 2026/11/12 ]] && grep -q "agros-arch-ok has no good signature by AgrOS's key (https://one.invalid/x86_64/agros-arch-ok.sig)" "$t/log" ||
        fail "agros-arch-ok signed $bad taken, or not said: $(cat "$t/agros/agros-arch-ok") / $(grep arch-ok "$t/log")"
done
echo 2026/11/01 >"$t/agros/agros-arch-ok"
SIG_ONE=none SIG_TWO=other "$t/auto-update"
[[ $(cat "$t/agros/agros-arch-ok") == 2026/11/01 && ! -e $t/agros/agros-arch-ok.new && ! -e $t/agros/agros-arch-ok.new.sig ]] ||
    fail "the copy kept not as it was with no good signature anywhere: $(cat "$t/agros/agros-arch-ok"; ls "$t/agros")"
echo "ok auto-update-install"
