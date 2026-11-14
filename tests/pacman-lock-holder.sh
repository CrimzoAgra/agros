#!/usr/bin/env bash
# pacman-lock-holder: pacman, paru or yay installing or upgrading holds pacman's lock; one only reading (a query, a
# search, info, what it would do printed, the files database read, paru's PKGBUILD download) doesn't, nor one on
# another database (-b/--dbpath, or another system's: -r/--root)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# Stand-ins: each a process whose command line has those arguments (after its own path); pgrep lists only it
printf '#!/bin/sh\nsleep 30\n' >"$t/fake"
printf '#!/bin/sh\necho "$FAKE"\n' >"$t/bin/pgrep"
chmod +x "$t/fake" "$t/bin/pgrep"
pids=()
cleanup() { local p; for p in "${pids[@]}"; do pkill -P "$p"; kill "$p"; done 2>/dev/null; wait 2>/dev/null; rm -rf "$t"; true; }
trap cleanup EXIT
holds() {
    "$t/fake" "$@" 2>/dev/null & pids+=($!)
    for _ in $(seq 50); do [[ $(tr '\0' ' ' <"/proc/$!/cmdline") == *"$t/fake"* ]] && break; sleep 0.02; done
    FAKE=$! PATH=$t/bin:$PATH "$here/.local/bin/pacman-lock-holder" /var/lib/pacman >/dev/null
}
for a in "-Syu" "-S foo" "-U x.pkg" "-Rns foo" "-Fy" "-Syi foo" "--sync --refresh" "--dbpath /var/lib/pacman/ -S foo" \
    "--dbpath=/var/lib/pacman -Syu" "-b /var/lib/pacman -S foo" "-b/var/lib/pacman -Su" "-r / -Syu" "--root=/ -S foo" ""; do
    # shellcheck disable=SC2086  # (the arguments, one per word)
    holds $a || fail "not taken for the lock's holder: pacman $a"
done
for a in "-Q" "-Qua" "-Qu" "--query foo" "-Ss foo" "-S -s foo" "-Si foo" "-Sl" "-Sg" "--sync --search foo" "-F foo" \
    "-T foo" "-G foo" "-Gp foo" "--dbpath /tmp/check -Sy" "--dbpath=/tmp/check -Syu" "-b /tmp/check -Sy" \
    "-b/tmp/check -Syu" "-r /mnt -Syu" "--root /mnt -S foo" "--root=/mnt -Syu" "-Sp foo" "--sync --print foo" "-Up x.pkg" \
    "-Rp foo" "-b/var/lib/pacman/cache -Ss foo" "-b/var/lib/pacman -Ss foo"; do
    # shellcheck disable=SC2086
    holds $a && fail "taken for the lock's holder: pacman $a"
done
# Asked about another database (the boot's download's): pacman on it holds that one's lock, a plain one doesn't
other() { "$t/fake" "$@" 2>/dev/null & pids+=($!)
    for _ in $(seq 50); do [[ $(tr '\0' ' ' <"/proc/$!/cmdline") == *"$t/fake"* ]] && break; sleep 0.02; done
    FAKE=$! PATH=$t/bin:$PATH "$here/.local/bin/pacman-lock-holder" /tmp/other >/dev/null; }
other --dbpath /tmp/other -Syuw || fail "pacman on the database asked about not taken for its lock's holder"
other -Syu && fail "a plain pacman taken for the holder of another database's lock"
other -r /tmp/other -Syu && fail "pacman on /tmp/other's own system (its list in /tmp/other/var/lib/pacman) taken for it"
# PACMAN_DB_DIR (pacman's own list, the tests' stand-in) and no folder asked about: that one, for the holder and the
# process alike
"$t/fake" -Syu 2>/dev/null & pids+=($!)
for _ in $(seq 50); do [[ $(tr '\0' ' ' <"/proc/$!/cmdline") == *"$t/fake"* ]] && break; sleep 0.02; done
FAKE=$! PACMAN_DB_DIR=/tmp/own PATH=$t/bin:$PATH "$here/.local/bin/pacman-lock-holder" >/dev/null ||
    fail "PACMAN_DB_DIR set, no folder given: a plain pacman not taken for the holder"
# A process gone between pgrep and its look: nothing said on stderr
[[ -z $(FAKE=999999999 PATH=$t/bin:$PATH "$here/.local/bin/pacman-lock-holder" 2>&1) ]] || fail "a gone process' error leaked"
echo "ok pacman-lock-holder"
