#!/usr/bin/env bash
# ci/sizes.py (the weekly size watch's comparison): the first week only records; then a package new this week and big
# is said with what pulled it in, a small one not; a set grown much is said; a package agros-trim.sh leaves out coming
# back, a name no repo has, a NoExtract pattern matching no file, and the two installed-system lists differing are
# each said; nothing said when nothing changed
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
d=$t/data
mkdir -p "$d"
# pkg <set> <name> <size> [depends...]: one package's pacman -Si block
pkg() {
    local set=$1 name=$2 sz=$3
    shift 3
    printf 'Repository      : extra\nName            : %s\nProvides        : %s\nDepends On      : %s\nInstalled Size  : %s\n\n' \
        "$name" "${name}-virt" "${*:-None}" "$sz" >>"$d/$set.si"
}
week1() {
    rm -f "$d"/*
    pkg iso hyprland '65.00 MiB' 'aquamarine>=0.9' cairo
    pkg iso aquamarine '1.50 MiB'
    pkg iso cairo '1,536.00 KiB'
    pkg inst hyprland '65.00 MiB' aquamarine cairo
    pkg inst aquamarine '1.50 MiB'
    pkg inst cairo '1.50 MiB'
    printf '%s\n' 'hyprland usr/share/hypr/wall0.png' 'hyprland usr/share/doc/hyprland/README' 'cairo usr/lib/libcairo.so' >"$d/iso.files"
    cp "$d/iso.files" "$d/inst.files"
    printf '%s\n' 'usr/share/hypr/wall*.png' 'usr/share/doc/*' '!usr/share/doc/fish/*' >"$d/live.pats"
    cp "$d/live.pats" "$d/inst.pats"
    cp "$d/live.pats" "$d/agros.pats"
    echo occt >"$d/iso.leftout"
}
run() { python3 "$here/ci/sizes.py" "$d" "${1:-}" "$t/out"; }

week1
run
[[ ! -s $t/out/report ]] || fail "the first week said something: $(cat "$t/out/report")"
grep -qxF '| The ISO: its packages | 3, 68 MiB installed |' "$t/out/table" || fail "the ISO's row: $(cat "$t/out/table")"
grep -qxF 'iso hyprland 66560' "$t/out/baseline" || fail "the baseline: $(cat "$t/out/baseline")"
cp "$t/out/baseline" "$t/week1"

# (nothing changed: nothing said, last week's numbers in the table)
run "$t/week1"
[[ ! -s $t/out/report ]] || fail "an unchanged week said something: $(cat "$t/out/report")"
grep -qxF '| A new install: its packages | 3, 68 MiB installed (last week 3, 68 MiB) |' "$t/out/table" ||
    fail "last week not in the row: $(cat "$t/out/table")"

# (the next week: a big package pulled in through what it provides, a small one, occt back, cairo grown, a name no
# repo has, a pattern gone stale, the installed lists apart)
week1
pkg iso libplasma '40.00 MiB'
pkg iso tiny '2.00 MiB'
pkg iso occt '30.00 MiB'
pkg iso qtengine '1.00 MiB' libplasma-virt tiny occt
sed -i 's/^Installed Size  : 1,536.00 KiB$/Installed Size  : 0.02 GiB/' "$d/iso.si"
echo nosuchpkg >"$d/inst.unknown"
sed -i '/wall0.png/d' "$d/iso.files"
echo 'usr/share/locale/*' >>"$d/inst.pats"
run "$t/week1"
r=$(cat "$t/out/report")
for s in 'The ISO: libplasma (40 MiB) is new this week, pulled in by qtengine' \
    'The ISO: occt (30 MiB) is new this week, pulled in by qtengine' \
    'The ISO: occt is back (agros-trim.sh leaves it out), pulled in by qtengine' \
    "A new install: its list asks for nosuchpkg, which no repo has (the build or the install fails on it)" \
    "agros-trim.sh, the live ISO's NoExtract pattern usr/share/hypr/wall*.png matches no file any more (renamed?): those files are unpacked again" \
    "agros-trim.sh, installed systems' NoExtract pattern usr/share/locale/* matches no file any more (renamed?): those files are unpacked again" \
    "agros-iso's agros-trim.sh (installed systems' NoExtract) and agros's agros-noextract.conf differ: keep them the same"; do
    grep -qxF -- "$s" <<<"$r" || fail "not said: $s
in: $r"
done
grep -q '^The ISO grew by 92 MiB this week (68 MiB → 160 MiB), most in libplasma (+40 MiB), occt (+30 MiB), cairo (+19 MiB)$' <<<"$r" ||
    fail "the growth not said: $r"
grep -q tiny <<<"$r" && fail "a small new package said: $r"
grep -q 'A new install grew\|A new install: .* is new' <<<"$r" && fail "the unchanged install said to have changed: $r"
grep -q 'agros-noextract.conf NoExtract pattern' <<<"$r" && fail "a pattern still matching said stale: $r"
echo "ok ci-sizes"
