#!/usr/bin/env bash
# boot-rollback (agros-boot, in the boot image): with agros.rollback=<snapshot>, a writable copy of it takes the root
# subvolume's place, the root's own subvolumes (/.snapshots, /var/lib/machines) moved into it, the root kept beside, and
# what it did written down (a second in a row counted); /.snapshots that can't be moved: everything undone, the root as
# it was; no agros.rollback: nothing done. (Folders stand in for subvolumes: btrfs's stand-in copies, lists, removes)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
top=$t/top
export BOOT_ROLLBACK_TOP=$top BOOT_ROLLBACK_CMDLINE=$t/cmdline
# btrfs: subvolume snapshot <a> <b> (copied), show <path> (a subvolume: its path under the root in $t/subs), delete
# <path>; find: the empty folders btrfs leaves in a snapshot for the root's subvolumes (those in $t/subs the copy has)
stub btrfs "case \"\$2\" in
    snapshot) cp -a \"\$3\" \"\$4\" ;;
    show) grep -qxF \"\${3#$top/@/}\" $t/subs ;;
    delete) rm -rf \"\$3\" ;;
esac"
stub find "while read -r rel; do [[ -d \$1/\$rel ]] && printf '%s\\0' \"\$1/\$rel\"; done <$t/subs"
# (systemctl: the restart after giving up, noted)
stub systemctl "echo \"systemctl \$*\" >>$t/calls"
export PATH=$t/bin:$PATH
run() { "$here/packages/agros-boot/boot-rollback"; }
# A root (@, "new": the update's) with its snapshots and machines, snapshot 5 ("old", with the empty folders a
# snapshot leaves for them)
fresh() {
    rm -rf "$top"; mkdir -p "$top/@/.snapshots/5/snapshot/.snapshots" "$top/@/.snapshots/5/snapshot/var/lib/machines" \
        "$top/@/var/lib/machines/m1"
    echo new >"$top/@/version"; echo old >"$top/@/.snapshots/5/snapshot/version"
    printf '%s\n' .snapshots var/lib/machines >"$t/subs"
}
echo 'BOOT_IMAGE=/@/.snapshots/5/snapshot/boot/vmlinuz root=UUID=1234 rw rootflags=defaults,subvol=@ agros.rollback=@/.snapshots/5/snapshot' >"$t/cmdline"

# Brought back: the snapshot is the root, its subvolumes in it, the update's root kept beside, written down
fresh
out=$(run)
[[ $(cat "$top/@/version") == old && -f $top/@/.snapshots/5/snapshot/version && -d $top/@/var/lib/machines/m1 ]] ||
    fail "the snapshot not made the root: $out"
broken=("$top"/@.agros-broken-*)
[[ ${#broken[@]} == 1 && $(cat "${broken[0]}/version") == new && ! -e $top/@.agros-new ]] || fail "the update's root not kept beside: $out"
[[ ! -e $t/calls ]] || fail "restarted after a rollback that went through: $(cat "$t/calls")"
read -r _ _ snap id n <"$top/@/var/lib/auto-update/rolled-back"
[[ $snap == @/.snapshots/5/snapshot && $id == "$(cat /proc/sys/kernel/random/boot_id)" && $n == 1 ]] ||
    fail "not written down: $(cat "$top/@/var/lib/auto-update/rolled-back")"
# ...a second in a row (the snapshot's own note of the first): counted
fresh
mkdir -p "$top/@/.snapshots/5/snapshot/var/lib/auto-update"
echo "2026-11-20 10:00 @/.snapshots/4/snapshot x 1" >"$top/@/.snapshots/5/snapshot/var/lib/auto-update/rolled-back"
run >/dev/null
[[ $(awk '{print $5}' "$top/@/var/lib/auto-update/rolled-back") == 2 ]] || fail "a second rollback in a row not counted"

# The snapshots can't be moved (the snapshot has no empty folder for them), the machines already moved: all undone,
# the root as it was
fresh
rmdir "$top/@/.snapshots/5/snapshot/.snapshots"
printf '%s\n' var/lib/machines .snapshots >"$t/subs"
out=$(run)
[[ $(cat "$top/@/version") == new && -d $top/@/var/lib/machines/m1 && -d $top/@/.snapshots/5 && ! -e $top/@.agros-new ]] &&
    ! compgen -G "$top/@.agros-broken-*" >/dev/null && [[ $out == *"restarts into the system as it was"* && $(cat "$t/calls") == "systemctl --no-block reboot" ]] ||
    fail "a failed rollback not undone, or the PC not restarted: $out"

# No agros.rollback: nothing done
fresh
sed -i 's/ agros.rollback=[^ ]*//' "$t/cmdline"
run >/dev/null
[[ $(cat "$top/@/version") == new && ! -e $top/@/var/lib/auto-update/rolled-back ]] || fail "acted with no agros.rollback"
echo "ok boot-rollback"
