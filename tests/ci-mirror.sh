#!/usr/bin/env bash
# ci/mirror.sh: the published repo fetched whole (every package the database lists, with its signature; the lists
# beside it where published), every signature checked against the key given; a database not signed by it, a package
# missing or tampered with, or a name that isn't a file's fails it. Uploaded packages first, the database last, the
# sync (which removes what the repo no longer has) after both; never from a folder without a database. A published
# repo here (curl a stand-in serving $t/site), signed with a key of the test's own
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export GNUPGHOME=$t/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
gpg --batch --quiet --armor --export >"$t/key.asc"
site=$t/site
mkdir -p "$site" "$t/bin"
# (curl: -o's file from $site, its HTTP code on stdout; 404 when $site hasn't it. Only the current copy asked for, a
# ?t= query past the CDN's: without one, nothing served)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/bash\nwhile (($#)); do case $1 in -o) o=$2; shift ;; -w|-m|--retry|--connect-timeout) shift ;; https://*) u=$1 ;; esac; shift; done
[[ $u == *"?t="[0-9]* ]] || { printf 000; exit 7; }\nu=${u%%%%\\?*}\nf=%s/${u#https://site/}\nif [[ -f $f ]]; then cp "$f" "$o"; printf 200; else printf 404; fi\n' "$site" >"$t/bin/curl"
# (rclone: its calls written down)
printf '#!/bin/sh\necho "$*" >>%s/rclone\n' "$t" >"$t/bin/rclone"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
sign() { rm -f "$1.sig"; gpg --batch --quiet --detach-sign "$1"; }
# db <file>...: agros.db listing those packages (signed)
db() {
    local s f i=0; s=$(mktemp -d)
    for f in "$@"; do i=$((i + 1)) && mkdir "$s/p$i" && printf '%%FILENAME%%\n%s\n\n%%NAME%%\nx\n' "$f" >"$s/p$i/desc"; done
    (cd "$s" && tar -czf "$site/agros.db" .)
    rm -rf "$s"
    sign "$site/agros.db"
}
for p in app-1-1-x86_64.pkg.tar.zst lib+x-2:1-1-any.pkg.tar.zst; do echo "$p" >"$site/$p" && sign "$site/$p"; done
db app-1-1-x86_64.pkg.tar.zst lib+x-2:1-1-any.pkg.tar.zst
cp "$site/agros.db" "$site/agros.db.tar.gz" && sign "$site/agros.db.tar.gz"
echo 'hyprland 0.50.0' >"$site/agros-approved"
echo 2026/11/16 >"$site/agros-arch-ok"
echo 1795689167 >"$site/agros-pass-time"
fetch() { rm -rf "$t/repo" "$t/repo".*; "$here/ci/mirror.sh" fetch https://site "$t/repo" "$t/key.asc" 2>&1; }

out=$(fetch) || fail "a good repo not fetched: $out"
[[ $(LC_ALL=C ls "$t/repo" | paste -sd' ') == "agros-approved agros-arch-ok agros-pass-time agros.db agros.db.sig agros.db.tar.gz agros.db.tar.gz.sig app-1-1-x86_64.pkg.tar.zst app-1-1-x86_64.pkg.tar.zst.sig lib+x-2:1-1-any.pkg.tar.zst lib+x-2:1-1-any.pkg.tar.zst.sig" ]] ||
    fail "not the published repo (no agros.files, no .sig of the lists: not published): $(ls "$t/repo")"
[[ $(paste -sd' ' "$t/repo.db") == "agros.db agros.db.sig agros.db.tar.gz agros.db.tar.gz.sig" &&
    $(paste -sd' ' "$t/repo.meta") == "agros-approved agros-arch-ok agros-pass-time" &&
    $(paste -sd' ' "$t/repo.pkgs") == "app-1-1-x86_64.pkg.tar.zst app-1-1-x86_64.pkg.tar.zst.sig lib+x-2:1-1-any.pkg.tar.zst lib+x-2:1-1-any.pkg.tar.zst.sig" ]] ||
    fail "the upload's lists: $(tail -n +1 "$t"/repo.db "$t"/repo.meta "$t"/repo.pkgs)"
# (a list's signature, published, fetched and checked too)
sign "$site/agros-approved"
out=$(fetch) && grep -qx agros-approved.sig "$t/repo.meta" || fail "agros-approved's signature not mirrored: $out"

# The upload: packages, then the lists, then the database, then the sync; from that folder to that remote
"$here/ci/mirror.sh" upload "$t/repo" r2:b/repo/x86_64 || fail "the upload failed"
[[ $(sed -E 's/^(copy|sync) .*--files-from [^ ]*\.([a-z]+) .*/\1 \2/; s/^sync .*/sync/' "$t/rclone" | paste -sd' ') == "copy pkgs copy meta copy db sync" ]] ||
    fail "the upload's order (packages, lists, database, sync): $(cat "$t/rclone")"
grep -q "^sync .* $t/repo r2:b/repo/x86_64\$" "$t/rclone" || fail "not synced from the fetched folder to the remote: $(cat "$t/rclone")"
# (never from a folder without a database: a sync would empty the mirror)
rm "$t/rclone" "$t/repo/agros.db"
"$here/ci/mirror.sh" upload "$t/repo" r2:b/repo/x86_64 >/dev/null 2>&1 && fail "a folder without a database uploaded"
[[ ! -e $t/rclone ]] || fail "rclone ran for a folder without a database: $(cat "$t/rclone")"

# Refused: the database signed by another key
cp "$site/agros.db.sig" "$t/good.sig"
GNUPGHOME=$t/other && mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'Other <o@agros.invalid>' default sign never >/dev/null 2>&1
sign "$site/agros.db"
GNUPGHOME=$t/gnupg
out=$(fetch) && fail "a database signed by another key mirrored"
grep -q "agros.db.sig isn't a good signature" <<<"$out" || fail "another key's signature not said: $out"
cp "$t/good.sig" "$site/agros.db.sig"
fetch >/dev/null || fail "the good repo again not fetched"
# Refused: a package tampered with (its signature no longer its), one listed but missing, one without a signature
cp "$site/app-1-1-x86_64.pkg.tar.zst" "$t/app" && echo evil >>"$site/app-1-1-x86_64.pkg.tar.zst"
out=$(fetch) && fail "a tampered package mirrored"
grep -q "app-1-1-x86_64.pkg.tar.zst.sig isn't a good signature" <<<"$out" || fail "the tampered package not said: $out"
mv "$t/app" "$site/app-1-1-x86_64.pkg.tar.zst"
mv "$site/lib+x-2:1-1-any.pkg.tar.zst.sig" "$t/libsig"
out=$(fetch) && fail "a package without its signature mirrored"
mv "$t/libsig" "$site/lib+x-2:1-1-any.pkg.tar.zst.sig"
db app-1-1-x86_64.pkg.tar.zst gone-1-1-any.pkg.tar.zst
out=$(fetch) && fail "a database listing a missing package mirrored"
grep -q "gone-1-1-any.pkg.tar.zst couldn't be read (HTTP 404)" <<<"$out" || fail "the missing package not said: $out"
# Refused: a name that isn't a bare file's (written outside the folder), and a database listing nothing
db ../app-1-1-x86_64.pkg.tar.zst
out=$(fetch) && fail "a database naming ../ mirrored"
grep -q "a file name that isn't one" <<<"$out" || fail "the bad name not said: $out"
db
out=$(fetch) && fail "a database listing no packages mirrored"
# Refused: no database signature published
db app-1-1-x86_64.pkg.tar.zst
rm "$site/agros.db.sig"
out=$(fetch) && fail "a database without its signature mirrored"
echo "ok ci-mirror"
