#!/usr/bin/env bash
# Signs the [agros] repo ci/build-repo.sh made, unsigned (CI's release job, in a container that never ran makepkg, paru,
# an AUR build script, a built package or a test; AgrOS's secret key imported for this step alone, gone after it):
#   ci/sign-repo.sh <dir>
# Each package without a signature gets one; one with a good signature by AgrOS's key keeps it (a published file kept
# as it was); one with any other .sig stops it (none should have one: never signed over). The database made again once
# they are (repo-add: it reads the packages' .PKGINFO, runs nothing of theirs), and signed; the
# upstream gate's list (agros-approved) and the day Arch last passed (agros-arch-ok) signed beside it.
# The key: the secret one in gpg's keyring, AgrOS's (ci/agros.asc's primary key, or a signing subkey of it: gpg picks
# the one it has the secret of); every signature made checked against ci/agros.asc alone after, so a secret that isn't
# AgrOS's, or a new subkey agros.asc doesn't have yet (clients couldn't check it), stops here, before anything goes out
set -euo pipefail
shopt -s extglob nullglob
root=$(cd "$(dirname "$0")/.." && pwd)
dir=$(cd "${1:?usage: sign-repo.sh <dir>}" && pwd)
asc=${AGROS_PUBKEY:-$root/ci/agros.asc}  # (another key file: a test's)
h=$(mktemp -d)
trap 'rm -rf "$h"' EXIT
gpg --homedir "$h" --batch --quiet --dearmor -o "$h/agros.gpg" <"$asc"
fpr=$(gpg --homedir "$h" --batch --with-colons --show-keys "$asc" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
[[ -n $fpr ]] || { echo "!! No key in $asc"; exit 1; }
good() { gpgv --keyring "$h/agros.gpg" "$1.sig" "$1" >/dev/null 2>&1; }
# sign <file>: <file>.sig made, and checked
sign() {
    rm -f "$1.sig"
    gpg --batch --yes --no-armor --local-user "$fpr" --detach-sign --output "$1.sig" "$1" ||
        { echo "!! $1 not signed: no secret key of $fpr (ci/agros.asc's) here, or it has a passphrase"; exit 1; }
    good "$1" || { echo "!! $1: signed, but its signature doesn't check against ci/agros.asc (a subkey it lacks?)"; exit 1; }
}
cd "$dir"
pkgs=(*.pkg.tar?(.zst|.xz|.gz|.bz2|.lz4|.lzo|.lrz|.Z))
((${#pkgs[@]})) || { echo "!! No packages in $dir"; exit 1; }
# (all checked before any is signed: one refused stops it with nothing signed)
unsigned=()
for f in "${pkgs[@]}"; do
    # (only plain files: a link would sign whatever it points at)
    [[ -f $f && ! -L $f ]] || { echo "!! $f isn't a plain file: refused"; exit 1; }
    if [[ -e $f.sig || -L $f.sig ]]; then
        good "$f" || { echo "!! $f has a .sig that isn't a good signature by AgrOS's key: refused, not signed over"; exit 1; }
    else
        unsigned+=("$f")
    fi
done
for f in "${unsigned[@]}"; do sign "$f"; done
kept=$((${#pkgs[@]} - ${#unsigned[@]})) signed=${#unsigned[@]}
echo "-- $signed packages signed, $kept kept with their published signature"
# The database (GitHub Pages serves no symlinks: its names as real files, each signed)
rm -f agros.db agros.db.tar.gz agros.files agros.files.tar.gz agros.db*.sig agros.files*.sig agros.db.tar.gz.old agros.files.tar.gz.old
repo-add -q agros.db.tar.gz "${pkgs[@]/#/./}"
for f in agros.db agros.files; do
    [[ ! -L $f ]] || cp --remove-destination "$(readlink -f "$f")" "$f"
    sign "$f.tar.gz"
    sign "$f"
done
echo "-- the database signed"
for f in agros-approved agros-arch-ok; do
    if [[ -e $f ]]; then sign "$f" && echo "-- $f signed"; fi
done
