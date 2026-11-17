#!/usr/bin/env bash
# agros-btrfs-member (90-agros-btrfs-members.rules): of a btrfs over several partitions, only its lowest devid listed by
# udisks (the one it shows as mounted; the others mounted the filesystem again at every click), whichever order they're
# probed in; a btrfs on one partition, an unreadable one: left as they are. btrfs and blkid stubbed
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# (each made-up device's superblock: its devid, its filesystem's member count and UUID)
cat >"$t/bin/btrfs" <<'S'
#!/bin/sh
case $3 in
    /dev/a4) printf 'fsid\t\tu-games\nnum_devices\t\t2\ndev_item.devid\t\t1\n' ;;
    /dev/a2) printf 'fsid\t\tu-games\nnum_devices\t\t2\ndev_item.devid\t\t2\n' ;;
    /dev/b1) printf 'fsid\t\tu-one\nnum_devices\t\t1\ndev_item.devid\t\t1\n' ;;
    *) exit 1 ;;
esac
S
printf '#!/bin/sh\n[ "$4" = UUID=u-games ] && printf "/dev/a2\\n/dev/a4\\n"\n[ "$4" = UUID=u-one ] && echo /dev/b1\nexit 0\n' >"$t/bin/blkid"
chmod +x "$t/bin"/*
h() { PATH=$t/bin:$PATH bash "$here/system/udev/agros-btrfs-member" "$1"; }
[[ $(h /dev/a2) == UDISKS_IGNORE=1 ]] || fail "the second member of a two-partition btrfs not hidden from udisks"
[[ -z $(h /dev/a4) ]] || fail "the lowest devid hidden too: the drive not listed at all"
[[ -z $(h /dev/b1) ]] || fail "a btrfs on one partition hidden"
[[ -z $(h /dev/gone) ]] || fail "an unreadable device hidden"
# The rule hands the helper its device, for btrfs only, and the PKGBUILD installs both where the rule looks
rule=$here/system/udev/90-agros-btrfs-members.rules
grep -q 'ENV{ID_FS_TYPE}=="btrfs"' "$rule" && grep -q 'IMPORT{program}="/usr/lib/udev/agros-btrfs-member $devnode"' "$rule" ||
    fail "the udev rule doesn't run the helper on btrfs devices"
grep -q '"$pkgdir/usr/lib/udev/agros-btrfs-member"' "$here/packages/agros-system/PKGBUILD" &&
    grep -q '"$pkgdir/usr/lib/udev/rules.d/90-agros-btrfs-members.rules"' "$here/packages/agros-system/PKGBUILD" ||
    fail "agros-system doesn't install the rule and its helper"
echo "ok btrfs-member"
