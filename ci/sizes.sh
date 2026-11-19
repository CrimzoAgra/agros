#!/usr/bin/env bash
# The weekly size watch (status.yml, before ci/status.sh; in an Arch container with git, python and python-yaml): what
# goes on the live ISO and on a new install, worked out from the package databases (nothing built or installed: pacman
# resolves each list as if into an empty disk), and the files of those packages; ci/sizes.py compares them with last
# week's and checks the NoExtract patterns still match.
#   ci/sizes.sh <out dir> [<last week's baseline>]
# - the ISO: agros-iso's package list as agros-trim.sh leaves it (run on a copy, as the build does); each of its
#   fallbacks (a name CachyOS's list no longer has, the LTS kernel kept, NoExtract not added: its lines that end in
#   "(agros-trim.sh)", otherwise only in the ISO build's log) said in the issue
# - a new install: the installer's list (netinstall.yaml's selected groups, whatever their platform: the cachyos
#   branch's installer installs each one). CachyOS's own pacstrap base (in its installer's package) isn't in it: the
#   same each week, so nothing to watch
set -euo pipefail
export LC_ALL=C
out=${1:?usage: ci/sizes.sh <out dir> [<last weeks baseline>]}
prev=${2:-}
here=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
d=$w/data
mkdir -p "$d" "$w/db"
# (its own pacman config and database: the container's own untouched. No signatures checked: only the databases are
# read, nothing is installed. CachyOS's x86_64 repo, as the ISO's pacman.conf has it: a new install on a newer CPU gets
# the same packages from its v3/v4 repo, a few percent apart in size, but every week measured the same way)
cat >"$w/pacman.conf" <<'EOF'
[options]
Architecture = x86_64
SigLevel = Never
[cachyos]
Server = https://mirror.cachyos.org/repo/$arch/$repo
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
[agros]
Server = https://crimzoagra.github.io/agros/$arch
EOF
pac() { pacman --config "$w/pacman.conf" --dbpath "$w/db" "$@"; }
pac -Sy >/dev/null
pac -Fy >/dev/null
# [agros]'s packages another repo has too, by the same name ("<name> <repo> <its version> <[agros]'s>" each; those
# the sets below take from that repo kept, after them): pacman takes a package from the first repo in pacman.conf that
# has its name, and [agros] is the last, so machines and new installs get that repo's (Quickshell without AgrOS's fix,
# a Caelestia AgrOS's CI never tested), said nowhere else
pac -Sl 2>/dev/null | awk '$1 == "agros" { ours[$2] = $3; next } { theirs[$2] = theirs[$2] ? theirs[$2] : $1 " " $3 }
    END { for (n in ours) if (n in theirs) print n, theirs[n], ours[n] }' | sort >"$w/shadowed" || true

git clone -q --depth 1 "${AGROS_ISO_GIT:-https://github.com/CrimzoAgra/agros-iso.git}" "$w/iso"
p=$w/iso/archiso
list() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1" | sort -u; }
cp "$p/packages_desktop.x86_64" "$p/packages.x86_64"
list "$p/packages.x86_64" >"$w/iso.before"
# (its messages are the build's msg2: on stderr, coloured where tput can; the colour codes taken out before reading)
bash "$w/iso/agros-trim.sh" "$p" >"$w/trim.log" 2>&1
sed 's/\x1b\[[0-9;]*m//g; s/\x1b([A-Z]//g' "$w/trim.log" |
    sed -n 's/^ *-> *\(.*(agros-trim\.sh)\)$/\1/p' >"$d/iso.trim"
list "$p/packages.x86_64" >"$w/iso.list"
comm -23 "$w/iso.before" "$w/iso.list" >"$d/iso.leftout"
python - "$p/airootfs/usr/share/agros/netinstall.yaml" >"$w/inst.list" <<'EOF'
import sys, yaml
def walk(g, on):
    on = g.get("selected", on)
    if not on:
        return
    for p in g.get("packages") or []:
        print(p["name"] if isinstance(p, dict) else p)  # (Calamares takes {name, description} too)
    for s in g.get("subgroups") or []:
        walk(s, on)
for g in yaml.safe_load(open(sys.argv[1])):
    walk(g, False)
EOF

# The patterns: the build's NoExtract lines as agros-trim.sh wrote them, and agros-system's file
pats() { sed -n 's/^NoExtract *= *//p' "$1" | sed 's/ *#.*//' | tr ' ' '\n' | sed '/^$/d'; }
pats "$p/pacman.conf" >"$d/live.pats"
pats "$p/airootfs/etc/pacman-more.conf" >"$d/inst.pats"
pats "$here/packages/agros-system/agros-noextract.conf" >"$d/agros.pats"

# Each set: every package it installs (dependencies too), their details and files. Names no repo has stop pacman's
# whole -Sp, each said ("target not found"): set aside (said in the issue) and the rest tried again. Anything else it
# stops on (a dependency nothing provides, a conflict, an empty list) is said instead of the set's sizes (<set>.error).
# A virtual dependency's provider: pacman's default, as the build's and the installer's --noconfirm take it
err() { sed '/^$/d; /^warning:/d' "$w/err" | paste -sd' ' | grep . || echo "pacman failed, saying nothing"; }
for set in iso inst; do
    : >"$d/$set.unknown"
    mapfile -t names <"$w/$set.list"
    if ! pac -Sp --noconfirm --print-format '%r/%n' "${names[@]}" >"$w/$set.pkgs" 2>"$w/err"; then
        sed -n 's/^error: target not found: //p' "$w/err" >"$d/$set.unknown"
        mapfile -t names < <(grep -vxFf "$d/$set.unknown" "$w/$set.list")
        if ! pac -Sp --noconfirm --print-format '%r/%n' "${names[@]}" >"$w/$set.pkgs" 2>"$w/err"; then
            err >"$d/$set.error"
            continue
        fi
    fi
    # (none listed: -Si and -Fl with no names would list every package in the repos)
    mapfile -t pkgs < <(grep / "$w/$set.pkgs")
    ((${#pkgs[@]})) || { echo "no packages listed" >"$d/$set.error"; continue; }
    pac -Si "${pkgs[@]}" >"$d/$set.si"
    # (a package the files database doesn't have yet, a moment behind: the rest still listed; the set's NoExtract
    # patterns then not checked, said)
    pac -Fl "${pkgs[@]}" >"$d/$set.files" 2>"$w/err" || err >"$d/$set.fileserror"
done
# (only those a set takes from that other repo: the ISO asks for agros/calamares by its repo, so CachyOS's own
# cachyos-calamares, the one AgrOS rebuilds, reaches neither)
cat "$w"/{iso,inst}.pkgs 2>/dev/null |
    awk 'NR == FNR { if (split($0, a, "/") == 2 && a[1] != "agros") taken[a[2]]; next } $1 in taken' - "$w/shadowed" \
    >"$d/shadowed" || true
python "$here/ci/sizes.py" "$d" "$prev" "$out"
