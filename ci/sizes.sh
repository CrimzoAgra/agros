#!/usr/bin/env bash
# The weekly size watch (status.yml, before ci/status.sh; in an Arch container with git, python and python-yaml): what
# goes on the live ISO and on a new install, worked out from the package databases (nothing built or installed: pacman
# resolves each list as if into an empty disk), and the files of those packages; ci/sizes.py compares them with last
# week's and checks the NoExtract patterns still match.
#   ci/sizes.sh <out dir> [<last week's baseline>]
# - the ISO: agros-iso's package list as agros-trim.sh leaves it (run on a copy, as the build does)
# - a new install: the installer's list (netinstall.yaml's selected groups, not the handheld ones). CachyOS's own
#   pacstrap base (in its installer's package) isn't in it: the same each week, so nothing to watch
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
# read, nothing is installed)
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

git clone -q --depth 1 "${AGROS_ISO_GIT:-https://github.com/CrimzoAgra/agros-iso.git}" "$w/iso"
p=$w/iso/archiso
list() { sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$1" | sort -u; }
cp "$p/packages_desktop.x86_64" "$p/packages.x86_64"
list "$p/packages.x86_64" >"$w/iso.before"
bash "$w/iso/agros-trim.sh" "$p" >/dev/null
list "$p/packages.x86_64" >"$w/iso.list"
comm -23 "$w/iso.before" "$w/iso.list" >"$d/iso.leftout"
python - "$p/airootfs/usr/share/agros/netinstall.yaml" >"$w/inst.list" <<'EOF'
import sys, yaml
def walk(g, on):
    on = g.get("selected", on)
    if not on or g.get("platform") == "handheld":
        return
    for p in g.get("packages") or []:
        print(p)
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

# Each set: every package it installs (dependencies too), their details and files. A name no repo has stops pacman's
# whole -Sp: each tried alone then, and the ones that fail set aside (said in the issue)
for set in iso inst; do
    mapfile -t names <"$w/$set.list"
    : >"$d/$set.unknown"
    if ! pac -Sp --noconfirm --print-format '%r/%n' "${names[@]}" >"$w/$set.pkgs" 2>/dev/null; then
        ok=()
        for n in "${names[@]}"; do
            if pac -Sp --noconfirm --print-format x "$n" >/dev/null 2>&1; then ok+=("$n"); else echo "$n" >>"$d/$set.unknown"; fi
        done
        pac -Sp --noconfirm --print-format '%r/%n' "${ok[@]}" >"$w/$set.pkgs"
    fi
    mapfile -t pkgs < <(grep / "$w/$set.pkgs")
    pac -Si "${pkgs[@]}" >"$d/$set.si"
    pac -Fl "${pkgs[@]}" >"$d/$set.files"
done
python "$here/ci/sizes.py" "$d" "$prev" "$out"
