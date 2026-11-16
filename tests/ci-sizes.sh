#!/usr/bin/env bash
# ci/sizes.py (the weekly size watch's comparison): the first week only records; then a package new this week and big
# is said with what pulled it in, a small one not; a set grown much is said; a package agros-trim.sh leaves out coming
# back, a name no repo has, a NoExtract pattern matching no file, and the two installed-system lists differing are
# each said; nothing said when nothing changed. A set pacman couldn't work out, or list the files of, is said, its
# patterns not checked, last week's baseline kept. Then ci/sizes.sh with a stand-in pacman and agros-iso: the lists as
# the build and the installer take them, names no repo has set aside, other pacman failures and an empty list said
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

# (one package grown: only it named; a [...] class in a pattern a class, not text)
week1
sed -i 's/^Installed Size  : 65.00 MiB$/Installed Size  : 125.00 MiB/' "$d/inst.si"
echo 'usr/lib/libcair[a-z].so' >>"$d/live.pats"
run "$t/week1"
r=$(cat "$t/out/report")
grep -qxF 'A new install grew by 60 MiB this week (68 MiB → 128 MiB), most in hyprland (+60 MiB)' <<<"$r" ||
    fail "a one-package growth: $r"
grep -q 'libcair' <<<"$r" && fail "a [...] pattern taken as text: $r"

# (the ISO not worked out, a new install's files not all listed: said; the ISO's row and last week's baseline kept;
# neither's patterns checked)
week1
rm "$d/iso.si"
echo "error: failed to prepare transaction (could not satisfy dependencies) :: unable to satisfy dependency 'libfoo' required by hyprland" >"$d/iso.error"
echo "error: package 'extra/cairo' was not found" >"$d/inst.fileserror"
sed -i '/wall0.png/d' "$d/iso.files" "$d/inst.files"
run "$t/week1"
r=$(cat "$t/out/report")
for s in "The ISO: pacman couldn't work out its packages, sizes not compared this week: error: failed to prepare transaction (could not satisfy dependencies) :: unable to satisfy dependency 'libfoo' required by hyprland" \
    "A new install: pacman couldn't list every package's files, its NoExtract patterns not checked this week: error: package 'extra/cairo' was not found"; do
    grep -qxF -- "$s" <<<"$r" || fail "not said: $s
in: $r"
done
grep -q 'matches no file' <<<"$r" && fail "a set's patterns checked without its files: $r"
grep -qxF '| The ISO: its packages | not worked out this week |' "$t/out/table" || fail "the ISO's row: $(cat "$t/out/table")"
[[ $(grep '^iso ' "$t/out/baseline") == "$(grep '^iso ' "$t/week1")" ]] ||
    fail "last week's ISO baseline not kept: $(cat "$t/out/baseline")"

# ci/sizes.sh, with a stand-in pacman (its repo: "<name> <size> [<dependency>...]" lines; -Sp resolves dependencies,
# says each unknown name, fails on a dependency no package is; -Si with no names would list everything: never asked;
# -Fl fails on the names in $t/nofiles) and a stand-in agros-iso
mkdir -p "$t/bin"
printf '%s\n' 'hyprland 65.00MiB aquamarine cairo' 'aquamarine 1.50MiB' 'cairo 1.50MiB' 'occt 30.00MiB' 'foot 2.00MiB' \
    'vim 4.00MiB' 'broken 1.00MiB libfoo' >"$t/repo"
: >"$t/nofiles"
cat >"$t/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >>"$T/pacman.log"
args=() op=
while (($#)); do
    case $1 in
        --config | --dbpath | --print-format) shift ;;
        --noconfirm) ;;
        -*) op=$1 ;;
        *) args+=("${1#*/}") ;;
    esac
    shift
done
size() { awk -v n="$1" '$1 == n { sub(/MiB$/, " MiB", $2); print $2; f = 1 } END { exit !f }' "$T/repo"; }
deps() { awk -v n="$1" '$1 == n { for (i = 3; i <= NF; i++) print $i }' "$T/repo"; }
case $op in
    -Sy | -Fy) ;;
    -Sp)
        ((${#args[@]})) || { echo "error: no targets specified (use -h for help)" >&2; exit 1; }
        rc=0
        for n in "${args[@]}"; do size "$n" >/dev/null || { echo "error: target not found: $n" >&2; rc=1; }; done
        ((!rc)) || exit 1
        declare -A by=()
        all=() todo=("${args[@]}")
        while ((${#todo[@]})); do
            n=${todo[0]} todo=("${todo[@]:1}")
            [[ " ${all[*]} " == *" $n "* ]] && continue
            if ! size "$n" >/dev/null; then
                printf 'error: failed to prepare transaction (could not satisfy dependencies)\n'
                printf ":: unable to satisfy dependency '%s' required by %s\n" "$n" "${by[$n]:-?}"
                exit 1
            fi >&2
            all+=("$n")
            for x in $(deps "$n"); do todo+=("$x"); by[$x]=$n; done
        done
        printf 'extra/%s\n' "${all[@]}" ;;
    -Si)
        ((${#args[@]})) || { touch "$T/si-all"; exit 1; }
        for n in "${args[@]}"; do
            printf 'Repository      : extra\nName            : %s\nDepends On      : %s\nInstalled Size  : %s\n\n' \
                "$n" "$(deps "$n" | paste -sd' ' | grep . || echo None)" "$(size "$n")"
        done ;;
    -Fl)
        rc=0
        for n in "${args[@]}"; do
            if grep -qx "$n" "$T/nofiles"; then echo "error: package 'extra/$n' was not found" >&2; rc=1; continue; fi
            echo "$n usr/share/doc/$n/README"
            [[ $n != hyprland ]] || echo "hyprland usr/share/hypr/wall0.png"
        done
        exit $rc ;;
esac
EOF
chmod +x "$t/bin/pacman"
iso=$t/iso
mkdir -p "$iso/archiso/airootfs/etc" "$iso/archiso/airootfs/usr/share/agros"
echo '[options]' >"$iso/archiso/pacman.conf"
echo '[options]' >"$iso/archiso/airootfs/etc/pacman-more.conf"
# (its agros-trim.sh: occt left out, the NoExtract lines written as the real one writes them)
cat >"$iso/agros-trim.sh" <<'EOF'
sed -i '/^occt$/d' "$1/packages.x86_64"
sed -i '/^\[options\]$/a NoExtract = usr/share/doc/* usr/share/hypr/wall*.png' "$1/pacman.conf"
sed -i '/^\[options\]$/a NoExtract = usr/share/doc/* # agros-iso' "$1/airootfs/etc/pacman-more.conf"
EOF
# isorepo <packages_desktop.x86_64> <netinstall.yaml>: agros-iso with those, committed
isorepo() {
    printf '%s\n' "$1" >"$iso/archiso/packages_desktop.x86_64"
    printf '%s\n' "$2" >"$iso/archiso/airootfs/usr/share/agros/netinstall.yaml"
    git -C "$iso" init -q
    git -C "$iso" add -A && git -C "$iso" -c user.name=t -c user.email=t@t commit -qm x
}
# (a selected group's packages, one as {name, description}, and its subgroups'; not an unselected group's, nor a
# handheld one's)
yaml='- name: base
  selected: true
  packages:
    - hyprland
    - name: foot
      description: the terminal
- name: handheld
  selected: true
  platform: handheld
  packages: [steamdeck-thing]
- name: extras
  selected: false
  packages: [vim]
- name: tools
  selected: true
  subgroups:
    - name: sub
      packages: [aquamarine]'
sizes() {
    rm -rf "$t/sout"
    T=$t PATH=$t/bin:$PATH AGROS_ISO_GIT=$iso "$here/ci/sizes.sh" "$t/sout" "$@" >/dev/null 2>"$t/err"
}
names() { sed -n "s/^$1 \([^ ]*\) .*/\1/p" "$t/sout/baseline" | paste -sd' '; }
isorepo $'# the desktop\nhyprland\nocct' "$yaml"
sizes || fail "ci/sizes.sh failed: $(cat "$t/err")"
[[ $(names iso) == "aquamarine cairo hyprland" ]] || fail "the ISO's packages: $(names iso)"
[[ $(names inst) == "aquamarine cairo foot hyprland" ]] || fail "a new install's packages: $(names inst)"
grep -qxF '| The ISO: its packages | 3, 68 MiB installed |' "$t/sout/table" || fail "the ISO's row: $(cat "$t/sout/table")"
grep -q "the live ISO's NoExtract pattern\|installed systems' NoExtract pattern\|no repo has\|couldn't" "$t/sout/report" &&
    fail "said of a good week: $(cat "$t/sout/report")"
cp "$t/sout/baseline" "$t/good"
# (a name no repo has set aside, the rest measured; a dependency no package is said as that, not as an unknown name,
# last week's baseline kept; a package -Fl can't list said)
isorepo $'hyprland\nbroken' "${yaml/    - hyprland/    - hyprland
    - nosuchpkg}"
echo foot >"$t/nofiles"
sizes "$t/good" || fail "ci/sizes.sh failed: $(cat "$t/err")"
r=$(cat "$t/sout/report")
for s in "A new install: its list asks for nosuchpkg, which no repo has (the build or the install fails on it)" \
    "The ISO: pacman couldn't work out its packages, sizes not compared this week: error: failed to prepare transaction (could not satisfy dependencies) :: unable to satisfy dependency 'libfoo' required by broken" \
    "A new install: pacman couldn't list every package's files, its NoExtract patterns not checked this week: error: package 'extra/foot' was not found"; do
    grep -qxF -- "$s" <<<"$r" || fail "not said: $s
in: $r"
done
grep -q 'broken, which no repo has' <<<"$r" && fail "a broken dependency said to be a name no repo has: $r"
[[ $(names inst) == "aquamarine cairo foot hyprland" ]] || fail "a new install not measured beside the unknown name: $(names inst)"
[[ $(grep '^iso ' "$t/sout/baseline") == "$(grep '^iso ' "$t/good")" ]] ||
    fail "last week's ISO baseline not kept: $(cat "$t/sout/baseline")"
: >"$t/nofiles"
# (an empty list: said, and -Si never asked for everything)
isorepo hyprland '- name: extras
  selected: false
  packages: [vim]'
sizes "$t/good" || fail "ci/sizes.sh failed on an empty list: $(cat "$t/err")"
grep -qxF "A new install: pacman couldn't work out its packages, sizes not compared this week: error: no targets specified (use -h for help)" "$t/sout/report" ||
    fail "an empty list not said: $(cat "$t/sout/report")"
[[ ! -e $t/si-all ]] || fail "pacman -Si asked with no names (every package in the repos)"
# (no out dir: its usage, and pacman never run)
rm -f "$t/pacman.log"
T=$t PATH=$t/bin:$PATH "$here/ci/sizes.sh" 2>"$t/err" && fail "ci/sizes.sh ran with no out dir"
grep -q 'usage: ci/sizes.sh <out dir>' "$t/err" || fail "no usage said: $(cat "$t/err")"
[[ ! -e $t/pacman.log ]] || fail "pacman run with no out dir"
echo "ok ci-sizes"
