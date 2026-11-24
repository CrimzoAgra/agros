#!/usr/bin/env bash
# soname-broken (auto-update's and update-apps' after the system update): an installed [agros] package one of whose
# libraries is gone from the system (libcava 1.0.0-1's libsndio.so.7, after sndio 1.11) named for a reinstall when
# [agros] has another build of it (the same version rebuilt for the new library, or a newer one); not one whose
# libraries are all there (in the library folder, the loader's cache, or its own files), nor when [agros]'s build is the
# one installed or older, nor when the reinstall would take anything else
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/usr/lib/priv" "$t/usr/bin"
: >"$t/usr/lib/libcava.so.1" && : >"$t/usr/bin/fine" && : >"$t/usr/lib/libgood.so.2" && : >"$t/usr/lib/priv/libown.so.1"
export SONAME_HOLD_LIBDIR=$t/usr/lib T=$t
# pacman: [agros]'s packages (libcava, fine installed; notmine not), their files, [agros]'s build ($REPO_VER, built
# $REPO_BUILT) and the one installed (1.0.0-1, built Mon 17), the dry run ($NEEDS beside the targets); readelf: libcava
# loads libsndio.so.7 (gone) and libc.so.6 (in the loader's cache), fine its own private library and libgood.so.2
# shellcheck disable=SC2016  # (expanded by the stand-ins)
cat >"$t/bin/pacman" <<'P'
#!/bin/bash
case " $* " in
    *" -Sl "*) printf '%s\n' 'agros libcava 1.0.0-1 [installed]' 'agros fine 1-1 [installed: 1-1]' 'agros notmine 1-1' ;;
    *" -Qlq "*) case ${*: -1} in libcava) printf '%s\n' "$T/usr/lib/" "$T/usr/lib/libcava.so.1" ;;
        fine) printf '%s\n' "$T/usr/bin/fine" "$T/usr/lib/priv/libown.so.1" ;; esac ;;
    *" -Si "*) [[ -n ${REPO_VER:-} ]] && printf 'Version         : %s\nBuild Date      : %s\n' "$REPO_VER" "${REPO_BUILT:-Thu 20}" ;;
    *" -Qi "*) printf 'Version         : 1.0.0-1\nBuild Date      : Mon 17\n' ;;
    *" -Sp "*) for a in "$@"; do [[ $a == agros/* ]] && echo "${a#agros/}"; done; [[ -z ${NEEDS:-} ]] || echo "$NEEDS" ;;
esac
exit 0
P
cat >"$t/bin/readelf" <<'R'
#!/bin/sh
case "${3##*/}" in
    libcava.so.1) printf '%s\n' " 0x1 (NEEDED) Shared library: [libsndio.so.7]" " 0x1 (NEEDED) Shared library: [libc.so.6]" ;;
    fine) printf '%s\n' " 0x1 (NEEDED) Shared library: [libown.so.1]" " 0x1 (NEEDED) Shared library: [libgood.so.2]" ;;
esac
R
printf '#!/bin/sh\necho "2 libs found in cache"\nprintf "\\tlibc.so.6 (libc6,x86-64) => /usr/lib/libc.so.6\\n"\n' >"$t/bin/ldconfig"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
broken() { "$here/.local/bin/soname-broken" 2>"$t/err"; }
o=$(REPO_VER=1.0.0-1 broken)
[[ $o == agros/libcava ]] || fail "libcava, its libsndio.so.7 gone and rebuilt in [agros] at the same version, not named: '$o' $(cat "$t/err")"
grep -q '^libcava needs libsndio.so.7, gone from the system: reinstalled from \[agros\] (1.0.0-1)$' "$t/err" ||
    fail "the reinstall not said: $(cat "$t/err")"
[[ $(REPO_VER=1.0.1-1 broken) == agros/libcava ]] || fail "libcava not named with a newer build in [agros]"
o=$(REPO_VER=1.0.0-1 REPO_BUILT='Mon 17' broken)
[[ -z $o ]] && grep -q "no other build of it yet" "$t/err" || fail "named with [agros]'s build the one installed: '$o' $(cat "$t/err")"
[[ -z $(REPO_VER=0.9-1 broken) ]] || fail "named with an older build in [agros]"
[[ -z $(broken) ]] || fail "named with [agros] not having it"
o=$(REPO_VER=1.0.0-1 NEEDS=sndio broken)
[[ -z $o ]] && grep -q "not reinstalled (libcava): it needs sndio too" "$t/err" || fail "named though its reinstall takes more: '$o' $(cat "$t/err")"
# (all of libcava's there: nothing named, nothing said)
: >"$t/usr/lib/libsndio.so.7"
o=$(REPO_VER=1.0.0-1 broken)
[[ -z $o && ! -s $t/err ]] || fail "named with all its libraries there: '$o' $(cat "$t/err")"
echo "ok soname-broken"
