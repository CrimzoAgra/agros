#!/usr/bin/env bash
# agros-personal: a pen drive already mounted (the file manager's automount) at a folder with a space in its name
# ("USB DISK", a FAT label's usual kind) is found. lsblk's raw output (-r) writes that space as \x20 (seen on this
# machine: PARTLABEL "Basic\x20data\x20partition"), so the folder it names doesn't exist as written
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mnt="$t/media/USB DISK"; mkdir -p "$mnt" "$t/bin"; : >"$mnt/dotfiles-personal.tar.gpg"
# (lsblk as real lsblk -nrpo NAME,RM,TYPE,MOUNTPOINT prints that drive)
printf '#!/bin/sh\necho "/dev/sdb 1 disk "\necho "/dev/sdb1 1 part %s"\n' "${mnt// /\\\\x20}" >"$t/bin/lsblk"
chmod +x "$t/bin/lsblk"
got=$(PATH=$t/bin:$PATH R=$here bash -c 'source "$R/.local/bin/agros-personal"; personal_drive')
[[ $got == "$mnt" ]] || fail "the mounted drive at \"$mnt\" not found (got: \"$got\")"
echo "ok personal-drive-space"
