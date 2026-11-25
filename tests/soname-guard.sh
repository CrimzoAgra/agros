#!/usr/bin/env bash
# soname-guard (agros-system's 00-agros-soname-guard.hook, before a pacman run installs anything): a run that takes away
# a library an installed gated package loads (a manual pacman -Syu: glslang's new soname, the Hyprland rebuild held by
# the gate) refused, said with what to do; not when that package is updated in the same run, nor for a library none of
# them loads. The hook: a PreTransaction one that aborts, given its targets, run on a library file going and on the
# gated packages' updates (the same list as agros-gate.conf's), installed by agros-system before snap-pac's snapshot
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/usr/bin"
: >"$t/usr/bin/Hyprland"
export T=$t
echo 'IgnorePkg = hyprland hyprutils' >"$AGROS_GATE"
# pacman: hyprland's files, who owns libglslang.so.16; readelf: Hyprland loads it and libc.so.6
# shellcheck disable=SC2016  # (expanded by the stand-ins)
stub pacman 'case " $* " in
    *" -Qlq -- hyprland "*) echo "$T/usr/bin/Hyprland" ;;
    *" -Qoq /usr/lib/libglslang.so.16 "*) echo glslang ;;
esac'
stub readelf '[[ ${*: -1} == */Hyprland ]] && printf " 0x1 (NEEDED) Shared library: [%s]\n" libglslang.so.16 libc.so.6; exit 0'
guard() { printf '%s\n' "$@" | PATH=$t/bin:$PATH "$here/.local/bin/soname-guard" 2>&1; }
o=$(guard usr/lib/libglslang.so.16 usr/lib/libglslang.so) &&
    fail "a run taking away Hyprland's libglslang.so.16, Hyprland held, not refused: '$o'"
[[ $o == *"glslang's update takes away libglslang.so.16, which hyprland loads"* && $o == *"Settings' Updates page"* ]] ||
    fail "the refusal doesn't say what goes, nor what to do: '$o'"
o=$(guard usr/lib/libglslang.so.16 hyprland) || fail "refused with Hyprland's update in the same run: '$o'"
o=$(guard usr/lib/libother.so.1) || fail "refused for a library no gated package loads: '$o'"
o=$(guard hyprland) || fail "refused with no library going: '$o'"
# The hook
h=$here/packages/agros-system/00-agros-soname-guard.hook
for l in 'When = PreTransaction' AbortOnFail NeedsTargets 'Exec = /usr/lib/agros/bin/soname-guard' 'Type = Path' 'Target = usr/lib/*.so.*'; do
    grep -qxF "$l" "$h" || fail "the hook lacks '$l'"
done
[[ $(sed -n '/^Target = [^/]*$/s/^Target = //p' "$h" | paste -sd' ') == "$(sed -n 's/^IgnorePkg = //p' "$here/packages/agros-system/agros-gate.conf")" ]] ||
    fail "the hook's packages aren't agros-gate.conf's"
grep -q '00-agros-soname-guard.hook' "$here/packages/agros-system/PKGBUILD" || fail "agros-system doesn't install the hook"
echo "ok soname-guard"
