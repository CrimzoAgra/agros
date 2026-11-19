#!/usr/bin/env bash
# newer.sh <site>: whether the [agros] repo published at <site> is already a newer commit's than this checkout's (CI's
# release job, its checkout with main's history). Runs on main go out one at a time, in order (ci.yml's concurrency),
# but a re-run of an older one (its failed jobs re-run from the Actions tab, a day later) builds and publishes that
# older commit's repo over the newer one already out: every machine then "updated" AgrOS's own packages back to older
# ones, until the next run. Writes newer=true when the published agros-system (r<commits>.<its commit>) is a commit
# that comes after this one on main as main is now; newer=false otherwise (none published yet, that commit not on
# main any more: main was pushed over, its own commit published again). To $GITHUB_OUTPUT (or stdout). The published
# database read with its signature checked against AgrOS's key alone (ci/agros.asc), as own-check.sh reads it: a
# database it can't read or check fails it, said, rather than guessing either way
set -uo pipefail
site=${1:?usage: newer.sh <site>}
root=$(cd "$(dirname "$0")/.." && pwd)
out=${GITHUB_OUTPUT:-/dev/stdout}
h=$(mktemp -d)
trap 'rm -rf "$h"' EXIT
# (?t=: Pages' CDN keeps a copy up to 10 minutes after a deploy; the query asks for the current one, as mirror.sh's)
stamp=$(date +%s)
code=$(curl -sS --retry 8 --retry-delay 15 -o "$h/db" -w '%{http_code}' "$site/agros.db?t=$stamp") || code=000
case $code in
    404) echo "-- nothing published yet"; echo "newer=false" >>"$out"; exit 0 ;;
    200) ;;
    *) echo "::error::$site/agros.db couldn't be read (HTTP $code)"; exit 1 ;;
esac
{ curl -fsS --retry 8 --retry-delay 15 -o "$h/db.sig" "$site/agros.db.sig?t=$stamp" &&
    gpg --homedir "$h" --batch --quiet --dearmor -o "$h/key.gpg" <"${AGROS_PUBKEY:-$root/ci/agros.asc}" &&
    gpgv --keyring "$h/key.gpg" "$h/db.sig" "$h/db" >/dev/null 2>&1; } ||
    { echo "::error::$site/agros.db's signature couldn't be read or doesn't check out"; exit 1; }
ver=$(bsdtar -xOf "$h/db" 2>/dev/null |
    awk '$0 == "%NAME%" { getline; n = $0 } $0 == "%VERSION%" { getline; if (n == "agros-system") print }' | head -n1)
pub=$(sed -n 's/^r[0-9]*\.\([0-9a-f]\{7,40\}\)-.*/\1/p' <<<"$ver")
newer=false
if [[ -z $pub ]]; then
    echo "-- the published agros-system (${ver:-none}) names no commit"
elif ! c=$(git -C "$root" rev-parse -q --verify "$pub^{commit}"); then
    echo "-- the published agros-system ($ver) is from a commit main no longer has"
elif [[ $c == "$(git -C "$root" rev-parse HEAD)" ]]; then
    echo "-- the published agros-system ($ver) is this commit's"
elif git -C "$root" merge-base --is-ancestor HEAD "$c" && git -C "$root" merge-base --is-ancestor "$c" origin/main; then
    echo "!! the published repo is a newer commit's (agros-system $ver): this run's, older, isn't put out over it"
    newer=true
else
    echo "-- the published agros-system ($ver) isn't a newer commit on main"
fi
echo "newer=$newer" >>"$out"
