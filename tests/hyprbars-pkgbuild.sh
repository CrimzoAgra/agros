#!/usr/bin/env bash
# agros-hyprbars' PKGBUILD (sourced as makepkg sources it, in a made-up repo): its version and its Hyprland bound come
# from the Hyprland it's built with (pacman -Q hyprland). The bound is that release series, CachyOS's relabelled
# build of it and every point release in it too (update-gate holds an approved Hyprland of the next series while this
# build of the old one is installed: its dry run's "breaks dependency"); the version is that Hyprland's, then the
# commits', newer for a newer Hyprland, and one makepkg takes (no ':', '-' or '/': a bad one failed CI's whole build)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v vercmp >/dev/null || { echo "skip hyprbars-pkgbuild (no vercmp)"; exit 0; }
r=$t/repo
mkdir -p "$r/packages/agros-hyprbars" "$r/.local/share/hyprbars" "$r/.local/bin"
cp "$here/packages/agros-hyprbars/PKGBUILD" "$r/packages/agros-hyprbars/"
cp "$here/.local/share/hyprbars/hyprbars.patch" "$r/.local/share/hyprbars/"
cp "$here/.local/bin/hyprbars-build" "$r/.local/bin/"
git init -q "$r"
git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm one
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub pacman '[[ $1 == -Q && $2 == hyprland ]] && echo "hyprland $HV"'
# pkg <hyprland's version>: the PKGBUILD's pkgver() then its depends, one a line
# shellcheck disable=SC2016  # (expanded by the PKGBUILD's shell)
pkg() { (cd "$r/packages/agros-hyprbars" && HV=$1 PATH=$t/bin:$PATH bash -c 'startdir=$PWD; . ./PKGBUILD; pkgver; echo; printf "%s\n" "${depends[@]}"'); }
for v in 0.57.2-1 0.57.2-1.1 0.57.0-3 0.9.3-2 0.10.0-1; do
    out=$(pkg "$v") || fail "the PKGBUILD failed with Hyprland $v: $out"
    ver=${out%%$'\n'*}
    [[ $ver =~ ^[A-Za-z0-9._+]+$ && $ver == [0-9]* ]] || fail "not a version makepkg takes, with Hyprland $v: $ver"
    s=${v%%-*}; s=${s%.*}
    want=$(printf '%s\n' "hyprland>=$s.0" "hyprland<${s%.*}.$((${s#*.} + 1)).0")
    [[ $(tail -n +2 <<<"$out") == "$want" ]] ||
        fail "Hyprland $v's bound isn't its series ($(paste -sd' ' <<<"$want")): $(tail -n +2 <<<"$out" | paste -sd' ')"
done
# (the series' bound by number: 0.9's next is 0.10, not "0.9" + 1 as text)
[[ $(pkg 0.9.3-2 | tail -1) == "hyprland<0.10.0" ]] || fail "0.9's series bound: $(pkg 0.9.3-2 | tail -1)"
# Newer for a newer Hyprland, a rebuild of it (Arch's pkgrel, CachyOS's relabel) and a point release
prev=
for v in 0.57.0-1 0.57.0-2 0.57.2-1 0.57.2-1.1 0.58.0-1 0.100.0-1; do
    # (read whole: head stopping early broke pkg's pipe, a failure under pipefail)
    ver=$(pkg "$v") && ver=${ver%%$'\n'*} || fail "the PKGBUILD failed with Hyprland $v"
    [[ -z $prev ]] || (($(vercmp "$ver" "$prev") > 0)) || fail "agros-hyprbars for Hyprland $v ($ver) isn't newer than $prev"
    prev=$ver
done
echo "ok hyprbars-pkgbuild"
