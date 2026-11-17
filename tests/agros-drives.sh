#!/usr/bin/env bash
# agros-drives: at login an internal Linux partition nothing mounts is mounted (udisks), once for a btrfs over two
# partitions, never the system's, a removable one, NTFS or one /etc/fstab lists; the Steam libraries on the internal
# drives are added to Steam's list, one it lists under another folder (same contentid) moved there, not added twice,
# one already listed left as it is, and Steam's list not touched while Steam is open
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
m=$t/media
mkdir -p "$m" "$t/fstab-mnt"
# The disks: the system's (/), a games btrfs over two partitions (one mounted already, at $t/fstab-mnt), an unmounted
# ext4 data drive, one /etc/fstab lists (noauto), a USB stick, a Windows NTFS one
cat >"$t/lsblk.json" <<EOF
{"blockdevices": [
 {"name":"/dev/sda","type":"disk","rm":false,"hotplug":false,"fstype":null,"uuid":null,"mountpoints":[null]},
 {"name":"/dev/sda1","type":"part","rm":false,"hotplug":false,"fstype":"btrfs","uuid":"root","mountpoints":["/","/home"]},
 {"name":"/dev/sda2","type":"part","rm":false,"hotplug":false,"fstype":"ext4","uuid":"data","mountpoints":[null]},
 {"name":"/dev/sda3","type":"part","rm":false,"hotplug":false,"fstype":"ext4","uuid":"listed","mountpoints":[null]},
 {"name":"/dev/sda4","type":"part","rm":false,"hotplug":false,"fstype":"ntfs","uuid":"windows","mountpoints":[null]},
 {"name":"/dev/nvme0n1p2","type":"part","rm":false,"hotplug":false,"fstype":"btrfs","uuid":"games","mountpoints":[null]},
 {"name":"/dev/nvme0n1p4","type":"part","rm":false,"hotplug":false,"fstype":"btrfs","uuid":"games","mountpoints":["$t/fstab-mnt"]},
 {"name":"/dev/sdb1","type":"part","rm":true,"hotplug":true,"fstype":"ext4","uuid":"usb","mountpoints":[null]}
]}
EOF
stub lsblk "cat '$t/lsblk.json'"
stub findmnt '[[ $* == *UUID=listed* ]]'
stub udisksctl "echo \"\$*\" >>'$t/mounted'; d='$m'/\${5##*/}; mkdir -p \"\$d\"; echo \"Mounted \$5 at \$d\""
stub pgrep "[[ -e '$t/steam-open' ]]"
run() { HOME=$t PATH=$t/bin:$PATH python3 -I "$here/.local/bin/agros-drives"; }
lib() { mkdir -p "$1/steamapps"; printf '"libraryfolder"\n{\n\t"contentid"\t\t"%s"\n\t"label"\t\t""\n}\n' "$2" >"$1/libraryfolder.vdf"; }
entry() {
    printf '\t"%s"\n\t{\n\t\t"path"\t\t"%s"\n\t\t"label"\t\t""\n\t\t"contentid"\t\t"%s"\n\t\t"apps"\n\t\t{\n\t\t\t"1"\t\t"2"\n\t\t}\n\t}\n' "$@"
}
vdf=$t/.local/share/Steam/steamapps/libraryfolders.vdf
mkdir -p "${vdf%/*}"
{ printf '"libraryfolders"\n{\n'; entry 0 "$t/.local/share/Steam" 10; entry 1 /mnt/games/SteamLibrary 11; printf '}\n'; } >"$vdf"
# On the drives: the games btrfs's library (Steam has it as /mnt/games/SteamLibrary: moved), a new one on the data drive
# (mounted at login), one in a game's own folder (not a library: inside one), one too deep to look for
lib "$t/fstab-mnt/@games/SteamLibrary" 11
mkdir -p "$t/fstab-mnt/@games/SteamLibrary/steamapps/common/Game/steamapps"
lib "$m/sda2/SteamLibrary" 12
lib "$m/sda2/a/b/c/d/SteamLibrary" 13

# Steam open: drives mounted, its list not touched
touch "$t/steam-open"; cp "$vdf" "$t/before"
run 2>/dev/null
cmp -s "$vdf" "$t/before" || fail "Steam's list changed while Steam was open"
[[ $(cat "$t/mounted") == "mount --no-user-interaction -b /dev/sda2" ]] ||
    fail "mounted: $(cat "$t/mounted") (only the unmounted internal ext4 should be)"
rm "$t/steam-open" "$t/mounted"

run >/dev/null
[[ $(cat "$t/mounted") == "mount --no-user-interaction -b /dev/sda2" ]] || fail "mounted the second time: $(cat "$t/mounted")"
got=$(grep -c '"path"' "$vdf")
((got == 3)) || fail "want 3 libraries, got $got: $(cat "$vdf")"
grep -q "\"path\"		\"$t/fstab-mnt/@games/SteamLibrary\"" "$vdf" || fail "the moved library's path not changed: $(cat "$vdf")"
grep -q '/mnt/games' "$vdf" && fail "the moved library's old path kept"
grep -q "\"path\"		\"$m/sda2/SteamLibrary\"" "$vdf" || fail "the new library not added"
grep -q '"contentid"		"12"' "$vdf" || fail "the new library's contentid not kept"
grep -qE 'common/Game|/d/SteamLibrary' "$vdf" && fail "a folder that isn't a library (or too deep) added"
grep -q '"1"		"2"' "$vdf" || fail "a library's games lost"
# Again: nothing to add, the list as it was
cp "$vdf" "$t/before"
run >/dev/null
cmp -s "$vdf" "$t/before" || fail "a second run changed Steam's list"
echo "ok agros-drives"
