#!/usr/bin/env bash
# pacnew-merge: a .pacnew the same as its file removed; the package's change merged into an edited file (diff3 from
# the previous version in pacman's cache), the file kept first; left alone where the changes overlap, the previous
# version isn't cached, the upgrade before left one too, or it's a file a bad merge locks you out with
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# pacman: -Qqo the owner (every file here: "pkg"), -Q its version ($HAVE)
stub pacman 'case $1 in -Qqo) echo pkg ;; -Q) echo "pkg ${HAVE:-2-1}" ;; esac'
export PATH=$t/bin:$PATH AGROS_ETC=$t/etc PACMAN_LOG=$t/pacman.log PACMAN_CACHE=$t/cache PACNEW_BACKUP=$t/backup
mkdir -p "$t/etc" "$t/cache" "$t/pkg/etc"
run() { "$here/.local/bin/pacnew-merge"; }
# the previous version, pkg 1-1, in the cache: its etc/app.conf (and etc/fstab, "a b c d e")
cached() {
    printf '%s\n' "$@" >"$t/pkg/etc/app.conf" && printf '%s\n' a b c d e >"$t/pkg/etc/fstab" &&
        bsdtar --zstd -cf "$t/cache/pkg-1-1-x86_64.pkg.tar.zst" -C "$t/pkg" etc
}
# pacman's log: the upgrade to 2-1 left /etc/app.conf.pacnew and /etc/fstab.pacnew (with $BEFORE: the one to 1-1 left
# app.conf's too)
logged() {
    { echo "[2026-11-01T10:00:00+0000] [ALPM] installed pkg (0.9-1)"
      [[ -z ${BEFORE:-} ]] || echo "[2026-11-02T10:00:00+0000] [ALPM] warning: /etc/app.conf installed as /etc/app.conf.pacnew"
      echo "[2026-11-02T10:00:00+0000] [ALPM] upgraded pkg (0.9-1 -> 1-1)"
      echo "[2026-11-03T10:00:00+0000] [ALPM] warning: /etc/app.conf installed as /etc/app.conf.pacnew"
      echo "[2026-11-03T10:00:00+0000] [ALPM] warning: /etc/fstab installed as /etc/fstab.pacnew"
      echo "[2026-11-03T10:00:00+0000] [ALPM] upgraded pkg (1-1 -> 2-1)"; } >"$t/pacman.log"
}

# The same as the file: removed
printf 'a\n' >"$t/etc/same.conf"; printf 'a\n' >"$t/etc/same.conf.pacnew"
out=$(run)
[[ ! -e $t/etc/same.conf.pacnew && $out == *"same.conf.pacnew: the same"* ]] || fail "an identical .pacnew not removed: $out"

# An edited file, the package's change elsewhere: merged, yours kept first, the .pacnew gone
cached one two three four five; logged
printf '%s\n' one TWO three four five >"$t/etc/app.conf"
printf '%s\n' one two three four FIVE >"$t/etc/app.conf.pacnew"
out=$(run)
[[ $(cat "$t/etc/app.conf") == $'one\nTWO\nthree\nfour\nFIVE' && ! -e $t/etc/app.conf.pacnew ]] || fail "not merged: $out / $(cat "$t/etc/app.conf")"
[[ $(cat "$t"/backup/app.conf.*) == $'one\nTWO\nthree\nfour\nfive' ]] || fail "yours not kept before the merge"

# The same lines changed by both: left as it is
printf '%s\n' one TWO three four five >"$t/etc/app.conf"
printf '%s\n' one 2 three four five >"$t/etc/app.conf.pacnew"
out=$(run)
[[ $(cat "$t/etc/app.conf") == $'one\nTWO\nthree\nfour\nfive' && -e $t/etc/app.conf.pacnew && $out == *overlap* ]] ||
    fail "an overlapping change merged: $out"

# The upgrade before left one too (never merged): left
printf '%s\n' one two three four FIVE >"$t/etc/app.conf.pacnew"
BEFORE=1 logged; out=$(run)
[[ -e $t/etc/app.conf.pacnew && $out == *"the upgrade before"* ]] || fail "merged across a .pacnew never merged: $out"
logged

# The previous version no longer cached: left
rm -f "$t/cache/pkg-1-1-x86_64.pkg.tar.zst"
out=$(run)
[[ -e $t/etc/app.conf.pacnew && $out == *"no longer in pacman's cache"* ]] || fail "merged without the previous version: $out"
cached one two three four five

# An installed version other than the upgrade's (a later upgrade, without a .pacnew): left
out=$(HAVE=3-1 run)
[[ -e $t/etc/app.conf.pacnew && -z $out ]] || fail "merged for a version not installed: $out"

# A file a bad merge locks you out with (here /etc/fstab, its merge clean: yours with E, the package's with A): left
printf '%s\n' a b c d E >"$t/etc/fstab"; printf '%s\n' A b c d e >"$t/etc/fstab.pacnew"
out=$(run)
[[ -e $t/etc/fstab.pacnew && $out != *fstab* ]] || fail "fstab merged: $out"
echo "ok pacnew-merge"
