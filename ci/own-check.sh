#!/usr/bin/env bash
# The packages in the repo to sign as CI meant to build them (CI's release job, first, before repo-add reads them):
#   AGROS_OWN_SUMS=<sha256sum's lines for them> [AGROS_PUBLISHED=<repo URL>] ci/own-check.sh <dir>
# The repo job runs AUR build scripts, root through sudo, in a privileged container: one could change an agros-*
# package there (agros-keyring: a key planted) or add one, and the release signs every package without a signature.
# So each package named agros-* (by its .PKGINFO too, not its file's name alone), or not readable, must be one of
# these, unchanged, and each of these must be there. The sums come from the agros job's output, which no other job
# can change (its artifact the repo job's root could replace).
# The rest must be ones the run builds: in aur/packages.txt, Quickshell or CachyOS's installer (built apart), or
# published before (the AUR packages those need), one file each; and none may replace another package (pacman -Syu
# swaps the system's for it unasked: sudo, say) or ship pacman's keyrings or settings. A new AUR dependency is refused
# too, said, until aur/packages.txt lists it.
# Every package, AgrOS's own too, read first: its .PKGINFO only as makepkg writes it (ci/pkginfo.sh), as repo-add,
# which the release runs after this, runs a line of another kind as code. Read here with bsdtar alone
set -euo pipefail
shopt -s nullglob
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=pkginfo.sh
. "$root/ci/pkginfo.sh"
dir=${1:?usage: own-check.sh <dir>}
sums=${AGROS_OWN_SUMS:?no sums from the agros job}
expected=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e 's|^.*/||' "$root/aur/packages.txt"; printf '%s\n' quickshell-git cachyos-calamares)
if [[ -n ${AGROS_PUBLISHED:-} ]]; then
    # (the published database's names, its signature checked against AgrOS's key alone; none yet, a 404: the list)
    # (?t=: Pages' CDN keeps a copy up to 10 minutes after a deploy, and an older database beside a newer signature
    # failed the check, the release stopped; the query asks for the current one, as mirror.sh's fetch)
    h=$(mktemp -d)
    trap 'rm -rf "$h"' EXIT
    stamp=$(date +%s)
    code=$(curl -sS --retry 3 -o "$h/db" -w '%{http_code}' "$AGROS_PUBLISHED/agros.db?t=$stamp") || code=000
    case $code in
        404) ;;
        200)
            { curl -fsS --retry 3 -o "$h/db.sig" "$AGROS_PUBLISHED/agros.db.sig?t=$stamp" &&
                gpg --homedir "$h" --batch --quiet --dearmor -o "$h/key.gpg" <"${AGROS_PUBKEY:-$root/ci/agros.asc}" &&
                gpgv --keyring "$h/key.gpg" "$h/db.sig" "$h/db" >/dev/null 2>&1 &&
                mkdir "$h/x" && bsdtar -xf "$h/db" -C "$h/x"; } ||
                { echo "!! the published database couldn't be read or verified"; exit 1; }
            expected+=$'\n'$(awk '/^%NAME%$/ { getline; print }' "$h"/x/*/desc /dev/null) ;;
        *) echo "!! the published database couldn't be read (HTTP $code)"; exit 1 ;;
    esac
fi
cd "$dir"
bad=0 seen=$'\n' pkgname=''  # (pkginfo's)
for f in *.pkg.tar*; do
    [[ $f == *.sig ]] && continue
    # (its .PKGINFO only as makepkg writes it, the file named after it: ci/pkginfo.sh)
    pkginfo "$f" || { bad=1; continue; }
    name=$pkgname
    if [[ $f == agros-* || $name == agros-* ]]; then
        want=$(awk -v f="$f" '$2 == f || $2 == "*" f { print $1; exit }' <<<"$sums")
        got=$(sha256sum <"$f" | cut -d' ' -f1)
        [[ -n $want && $got == "$want" ]] || { echo "!! $f ($name) isn't as the agros job built it: refused"; bad=1; }
        continue
    fi
    grep -qxF -- "$name" <<<"$expected" ||
        { echo "!! $f: $name isn't one this run builds or published before: refused (a new AUR dependency: add it to aur/packages.txt)"; bad=1; }
    # (one file a name: another under an expected name took the database's entry)
    [[ $seen != *$'\n'"$name"$'\n'* ]] || { echo "!! $f: a second package named $name: refused"; bad=1; }
    seen+=$name$'\n'
    info=$(bsdtar -xOqf "$f" .PKGINFO 2>/dev/null) || info=
    rel=$(sed -n 's/^replaces = //p' <<<"$info" | paste -sd' ')
    [[ -z $rel ]] || { echo "!! $f replaces $rel: refused"; bad=1; }
    # (the whole listing read into a variable first: no early reader on a pipe)
    list=$(bsdtar -tf "$f" 2>/dev/null) || list=
    pac=$(grep -E '^(usr/share/pacman/.*[^/]|etc/pacman\.conf|etc/pacman\.d/.*[^/])$' <<<"$list" | paste -sd' ') || true
    [[ -z $pac ]] || { echo "!! $f ships pacman's keyrings or settings ($pac): refused"; bad=1; }
done
while read -r _ f; do
    f=${f#\*}
    [[ -z $f || -f $f ]] || { echo "!! $f, built by the agros job, isn't here"; bad=1; }
done <<<"$sums"
((bad == 0)) || exit 1
echo "-- AgrOS's own packages as the agros job built them, the rest ones this run builds"
