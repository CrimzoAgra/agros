#!/usr/bin/env bash
# soname-hold (update-gate's): an update that takes away a library an installed [agros] package loads (sndio 1.11:
# libsndio.so.7 gone, libcava built against it, Caelestia not starting) holds that library's package, unless [agros]'s
# newer build of the package comes in the same update; not when the library's new version still has that soname, nor
# when it names no sonames at all (no guess). Through update-gate: held in its pacman.conf, said
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/usr/lib"
: >"$t/usr/lib/libcava.so.1" && : >"$t/usr/lib/libsndio.so.7"
export SONAME_HOLD_LIBDIR=$t/usr/lib T=$t
# pacman: [agros]'s installed packages, the update ($PENDING: "name" lines), libcava's files, who owns a library, and
# sndio's new version's provides ($PROVIDES); readelf: libcava's library loads libsndio.so.7
# shellcheck disable=SC2016  # (expanded by the stand-ins)
cat >"$t/bin/pacman" <<'P'
#!/bin/bash
case " $* " in
    *" -Sl "*) printf '%s\n' 'agros libcava 1.0.0-1 [installed]' 'agros notmine 1-1' ;;
    *" -Qu "*) for p in $PENDING; do echo "$p 1-1 -> 2-1"; done ;;
    *" -Qlq "*) [[ ${*: -1} == libcava ]] && printf '%s\n' "$T/usr/lib/" "$T/usr/lib/libcava.so.1" ;;
    *" -Qoq "*) [[ ${*: -1} == "$T/usr/lib/libsndio.so.7" ]] && echo sndio ;;
    *" -Si "*) [[ ${*: -1} == sndio ]] && printf 'Version         : 2-1\nProvides        : %s\nDepends On      : glibc\n' "$PROVIDES" ;;
esac
exit 0
P
printf '#!/bin/sh\n[ "${3##*/}" = libcava.so.1 ] && echo " 0x0000000000000001 (NEEDED)             Shared library: [libsndio.so.7]"\nexit 0\n' >"$t/bin/readelf"
chmod +x "$t/bin/pacman" "$t/bin/readelf"
export PATH=$t/bin:$PATH
hold() { "$here/.local/bin/soname-hold" "$t/pacman.conf"; }
o=$(PENDING=sndio PROVIDES='libsndio.so=9-64' hold)
[[ $o == "sndio libcava libsndio.so.7" ]] || fail "the update taking away libcava's libsndio.so.7 not held: '$o'"
o=$(PENDING='sndio libcava' PROVIDES='libsndio.so=9-64' hold)
[[ -z $o ]] || fail "held though libcava's own newer build comes in the same update: '$o'"
o=$(PENDING=sndio PROVIDES='libsndio.so=7-64' hold)
[[ -z $o ]] || fail "held though the new version keeps libsndio.so.7: '$o'"
o=$(PENDING=sndio PROVIDES='None' hold)
[[ -z $o ]] || fail "held on a guess (the new version names no sonames): '$o'"
o=$(PENDING=other PROVIDES='libsndio.so=9-64' hold)
[[ -z $o ]] || fail "held with sndio not updated: '$o'"
# Through update-gate: held in its pacman.conf (with no gated packages too), said
export AGROS_GATE=$t/gate.conf AGROS_GATE_CACHE=$t/approved
: >"$AGROS_GATE"
printf '%s\n' '[options]' 'Architecture = auto' '' '[agros]' 'Server = https://agros.invalid/x86_64' >"$t/pacman.conf"
o=$(PENDING=sndio PROVIDES='libsndio.so=9-64' "$here/.local/bin/update-gate" "$t/pacman.conf" "$t/out.conf")
[[ $o == *"sndio (waits for AgrOS's rebuild of libcava: its update takes away libsndio.so.7, which libcava loads)"* ]] ||
    fail "update-gate didn't say sndio waits: '$o'"
grep -qx 'IgnorePkg = sndio' "$t/out.conf" || fail "update-gate didn't hold sndio: $(cat "$t/out.conf")"
echo "ok soname-hold"
