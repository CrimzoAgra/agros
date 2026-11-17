#!/usr/bin/env bash
# AgrOS's own packages in the repo to sign exactly those CI's agros job built (CI's release job, before it signs):
#   AGROS_OWN_SUMS=<sha256sum's lines for them> ci/own-check.sh <dir>
# The repo job runs AUR build scripts, root through sudo, in a privileged container: one could change an agros-*
# package there (agros-keyring: a key planted) or add one, and the release signs every package without a signature.
# So each package named agros-* (by its .PKGINFO too, not its file's name alone), or not readable, must be one of
# these, unchanged, and each of these must be there. The sums come from the agros job's output, which no other job
# can change (its artifact the repo job's root could replace)
set -euo pipefail
shopt -s nullglob
dir=${1:?usage: own-check.sh <dir>}
sums=${AGROS_OWN_SUMS:?no sums from the agros job}
cd "$dir"
bad=0
for f in *.pkg.tar*; do
    [[ $f == *.sig ]] && continue
    name=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p') || name=
    [[ $f == agros-* || $name == agros-* || -z $name ]] || continue
    want=$(awk -v f="$f" '$2 == f || $2 == "*" f { print $1; exit }' <<<"$sums")
    got=$(sha256sum <"$f" | cut -d' ' -f1)
    [[ -n $want && $got == "$want" ]] || { echo "!! $f (${name:-no .PKGINFO}) isn't as the agros job built it: refused"; bad=1; }
done
while read -r _ f; do
    f=${f#\*}
    [[ -z $f || -f $f ]] || { echo "!! $f, built by the agros job, isn't here"; bad=1; }
done <<<"$sums"
((bad == 0)) || exit 1
echo "-- AgrOS's own packages as the agros job built them"
