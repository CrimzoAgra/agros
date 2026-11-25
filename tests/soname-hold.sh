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

# --held (update-gate's, the gate's set held): a library Hyprland loads whose update takes it away, held with it, though
# it names no sonames (glslang, Hyprland needing it by name alone): looked for in its new package's own files (pacman's
# download, else the mirror's); what needs it by name held too (libplacebo: maybe built for the new soname). Not mesa,
# whose new package still has Hyprland's libgbm.so.1; nothing when Hyprland's update comes with it
command -v bsdtar >/dev/null || { skipped "no bsdtar"; echo "ok soname-hold (no bsdtar: --held not checked)"; exit 0; }
mkdir -p "$t/usr/bin" "$t/pkgs"
: >"$t/usr/bin/Hyprland" && : >"$t/usr/lib/libglslang.so.16" && : >"$t/usr/lib/libgbm.so.1"
# pkg <file> <its library>...: a package with those files
pkg() { local d f=$1; shift; d=$(mktemp -d); mkdir -p "$d/usr/lib"; for l; do : >"$d/usr/lib/$l"; done; bsdtar -cf "$t/pkgs/$f" --zstd -C "$d" usr; rm -rf "$d"; }
pkg glslang-2-1.pkg.tar.zst libglslang.so.17 libglslang.so
pkg glslang-1.1-1.pkg.tar.zst libglslang.so.16 libglslang.so
pkg mesa-2-1.pkg.tar.zst libgbm.so.1 libEGL_mesa.so.0
# pacman: hyprland installed (0.57.2-1) and its new version ($NEW), the update ($PENDING, Hyprland's own in it as pacman
# lists one held), glslang's new package ($GLSLANG: in pacman's cache) and mesa's (at the mirror, curl's), who needs
# glslang; readelf: Hyprland loads libglslang.so.16 and libgbm.so.1
# shellcheck disable=SC2016
cat >"$t/bin/pacman" <<'P'
#!/bin/bash
echo "pacman $*" >>"$T/calls"
case " $* " in
    *" -Sl "*) ;;
    *" -Qu "*) echo "hyprland 0.57.2-1 -> $NEW [ignored]"; for p in $PENDING; do echo "$p 1-1 -> 2-1"; done ;;
    *" -Q -- hyprland "*) echo "hyprland 0.57.2-1" ;;
    *" -Si "*" hyprland "*) echo "Version         : $NEW" ;;
    *" -Si "*) printf 'Version         : 2-1\nProvides        : None\n' ;;
    *" -Sddp "*" glslang "*) echo "file://$T/pkgs/$GLSLANG" ;;
    *" -Sddp "*" mesa "*) echo "https://mirror.invalid/extra/mesa-2-1.pkg.tar.zst" ;;
    *" -Qi -- glslang "*) echo "Required By     : hyprland libplacebo shaderc" ;;
    *" -Qlq -- hyprland "*) echo "$T/usr/bin/Hyprland" ;;
    *" -Qoq "*libglslang.so.16*) echo glslang ;;
    *" -Qoq "*libgbm.so.1*) echo mesa ;;
esac
exit 0
P
printf '#!/bin/sh\n[ "${3##*/}" = Hyprland ] && printf " 0x1 (NEEDED) Shared library: [%%s]\\n" libglslang.so.16 libgbm.so.1\nexit 0\n' >"$t/bin/readelf"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "curl $*" >>"$T/calls"\n[[ ${*: -1} == https://mirror.invalid/extra/mesa-2-1.pkg.tar.zst && -z $MIRRORDOWN ]] || exit 7\ncat "$T/pkgs/mesa-2-1.pkg.tar.zst"\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
export SONAME_HOLD_CACHE=$t/libs MIRRORDOWN=
echo 'IgnorePkg = hyprland hyprutils' >"$AGROS_GATE"
echo 'hyprland 0.57.2' >"$AGROS_GATE_CACHE"
gate() { "$here/.local/bin/update-gate" "$t/pacman.conf" "$t/out.conf" "$@"; }
ign() { pacman-conf --config "$t/out.conf" IgnorePkg | sort | paste -sd' '; }
# A new soname, Hyprland's new version not checked yet: glslang held with it (and libplacebo), mesa not
: >"$t/calls"
o=$(NEW=0.58.0-1 PENDING='glslang mesa libplacebo' GLSLANG=glslang-2-1.pkg.tar.zst gate)
[[ $o == *"glslang (waits for hyprland's update: its update takes away libglslang.so.16, which hyprland loads)"* &&
    $o == *"libplacebo (waits with glslang for hyprland's update:"* && $o != *mesa* && $(ign) == "glslang hyprland hyprutils libplacebo" ]] ||
    fail "glslang's new soname not held with the held Hyprland (or mesa held): '$o' / $(ign)"
grep -q '^curl .*mesa-2-1' "$t/calls" || fail "mesa's new package not read from the mirror: $(cat "$t/calls")"
# (each package read once: kept by its file name, the mirror not asked again)
: >"$t/calls"
o=$(NEW=0.58.0-1 PENDING='glslang mesa' GLSLANG=glslang-2-1.pkg.tar.zst MIRRORDOWN=1 gate)
[[ $o == *"glslang (waits for hyprland's update"* && $o != *mesa* ]] && ! grep -q '^curl .*mirror' "$t/calls" ||
    fail "a package's files not kept: '$o' / $(cat "$t/calls")"
# The same soname in glslang's new version: not held
o=$(NEW=0.58.0-1 PENDING='glslang mesa' GLSLANG=glslang-1.1-1.pkg.tar.zst gate)
[[ -z $o || $o == "hyprland 0.57.2-1 -> 0.58.0-1" ]] && [[ $(ign) == "hyprland hyprutils" ]] ||
    fail "glslang held though its new version keeps libglslang.so.16: '$o' / $(ign)"
# Its new package not to be had (the mirror unreachable): not held on a guess. --offline (the shutdown's): the mirror
# not asked, pacman's download alone
rm -rf "$SONAME_HOLD_CACHE"
o=$(NEW=0.58.0-1 PENDING='mesa' MIRRORDOWN=1 gate)
[[ $o == "hyprland 0.57.2-1 -> 0.58.0-1" ]] || fail "held with mesa's new package not to be had: '$o'"
: >"$t/calls"
o=$(NEW=0.58.0-1 PENDING='glslang mesa' GLSLANG=glslang-2-1.pkg.tar.zst gate --offline)
[[ $o == *"glslang (waits for hyprland's update"* ]] && ! grep -q '^curl' "$t/calls" ||
    fail "--offline asked the mirror, or held nothing: '$o' / $(cat "$t/calls")"
# Hyprland approved, its update in the same one (or Arch's rebuild of the same version, let through unchecked): nothing
# held, the gate open
for new in 0.58.0-1 0.57.2-2; do
    echo 'hyprland 0.58.0' >>"$AGROS_GATE_CACHE"
    o=$(NEW=$new PENDING='glslang mesa libplacebo' GLSLANG=glslang-2-1.pkg.tar.zst gate)
    [[ -z $o && -z $(ign) ]] && ! grep -q agros-gate "$t/out.conf" || fail "held though Hyprland $new comes with glslang: '$o' / $(ign)"
done
echo "ok soname-hold"
