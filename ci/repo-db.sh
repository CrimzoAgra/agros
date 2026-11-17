#!/usr/bin/env bash
# The [agros] repo's database made from the packages in <dir> (CI's release job, after ci/own-check.sh and the hold;
# the key never there: the sign job signs the database as this leaves it, ci/sign-repo.sh):
#   ci/repo-db.sh <dir>
# pacman's repo-add reads each package's .PKGINFO with bash's declare, and a line of a kind makepkg doesn't write runs
# as code: so every package is read first (ci/pkginfo.sh), the published ones a hold brought back too, not only those
# own-check.sh read. Then the database read back as pacman reads it: one entry a package, its folder, name, version and
# file what that package's .PKGINFO says, or it stops (a name repo-add read another way than pacman, one entry over
# another), nothing to sign
set -euo pipefail
shopt -s extglob nullglob
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=pkginfo.sh
. "$root/ci/pkginfo.sh"
cd "${1:?usage: repo-db.sh <dir>}"
pkgs=(*.pkg.tar?(.zst|.xz|.gz|.bz2|.lz4|.lzo|.lrz|.Z))
((${#pkgs[@]})) || { echo "!! No packages in $PWD"; exit 1; }
entries=() pkgname='' pkgver=''  # (the last two pkginfo's)
for f in "${pkgs[@]}"; do
    [[ -f $f && ! -L $f ]] || { echo "!! $f isn't a plain file: refused"; exit 1; }
    pkginfo "$f" || exit 1
    entries+=("$pkgname-$pkgver $f $pkgname $pkgver")
done
rm -f agros.db agros.db.tar.gz agros.files agros.files.tar.gz agros.db*.sig agros.files*.sig agros.db.tar.gz.old agros.files.tar.gz.old
repo-add -q agros.db.tar.gz "${pkgs[@]/#/./}"
# GitHub Pages serves no symlinks: the database's names as real files
for f in agros.db agros.files; do
    [[ ! -L $f ]] || cp --remove-destination "$(readlink -f "$f")" "$f"
done
# Each entry: "<folder> <%FILENAME%> <%NAME%> <%VERSION%>", each field's lines as pacman reads them (a header, its value
# lines up to a blank one: a value that reads as a header is a value)
h=$(mktemp -d)
trap 'rm -rf "$h"' EXIT
want=$(printf '%s\n' "${entries[@]}" | LC_ALL=C sort)
for db in agros.db agros.files; do
    mkdir "$h/$db" && bsdtar -xf "$db" -C "$h/$db" || { echo "!! $db couldn't be read back"; exit 1; }
    got=$(for d in "$h/$db"/*/; do
        d=${d%/}
        awk -v dir="${d##*/}" '
            /^%[A-Z0-9]+%$/ { k = $0; while ((getline l) > 0 && l != "") v[k] = (k in v ? v[k] "," : "") l; next }
            END { print dir, v["%FILENAME%"], v["%NAME%"], v["%VERSION%"] }' "$d/desc" || echo "$d: no desc"
    done | LC_ALL=C sort)
    [[ $got == "$want" ]] || {
        echo "!! $db doesn't list the packages here as their .PKGINFO names them: nothing to sign"
        diff <(echo "$want") <(echo "$got") | head -20 || true  # (cut off by head: not the failure)
        exit 1
    }
done
echo "-- the database made: ${#pkgs[@]} packages, each listed as its .PKGINFO names it"
