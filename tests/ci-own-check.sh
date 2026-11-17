#!/usr/bin/env bash
# ci/own-check.sh (CI's release, before it signs): AgrOS's own packages exactly those the agros job built, by their sums
# (that job's output): one changed, one added (by its file's name or only by its .PKGINFO's: agros-keyring under
# another file name), one not readable, or one of the agros job's missing, and nothing is signed. The rest only ones
# the run builds (aur/packages.txt, Quickshell, or in the published database, its signature checked): one planted, a
# second under an expected name, one that replaces another package or ships pacman's keyrings refused; a pacman hook
# isn't. No sums: refused
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v bsdtar >/dev/null || { skipped "no bsdtar"; echo "skip ci-own-check (no bsdtar)"; exit 0; }
r=$t/repo
mkdir "$r"
# pkg <file> <name> [<text>] [<more .PKGINFO lines>] [<the file it ships>]: a package of that name
pkg() {
    local s p=${5:-data}; s=$(mktemp -d)
    printf 'pkgname = %s\npkgver = 1-1\n%s' "$2" "${4:+$4$'\n'}" >"$s/.PKGINFO"
    mkdir -p "$s/$(dirname "$p")" && echo "${3:-x}" >"$s/$p"
    (cd "$s" && bsdtar -cf "$r/$1" --zstd .PKGINFO "$p")
    rm -rf "$s"
}
pkg agros-keyring-1-1-any.pkg.tar.zst agros-keyring
pkg agros-hyprbars-1-1-x86_64.pkg.tar.zst agros-hyprbars && echo sig >"$r/agros-hyprbars-1-1-x86_64.pkg.tar.zst.sig"
sums=$(cd "$r" && sha256sum agros-keyring-1-1-any.pkg.tar.zst && sha256sum -b agros-hyprbars-1-1-x86_64.pkg.tar.zst)
pkg quickshell-git-1-1-x86_64.pkg.tar.zst quickshell-git x 'provides = quickshell'
pkg papirus-folders-1-1-any.pkg.tar.zst papirus-folders x 'conflicts = papirus-folders-git' usr/share/libalpm/hooks/papirus-folders.hook
cp -r "$r" "$t/good"
check() { AGROS_OWN_SUMS=$sums "$here/ci/own-check.sh" "$r" 2>&1; }
o=$(check) || fail "AgrOS's own packages as built, and the AUR's listed, refused: $o"
# (each case on the good repo again)
for c in changed added renamed unreadable missing planted second misnamed replaces keyrings settings; do
    rm -rf "$r" && cp -r "$t/good" "$r"
    case $c in
        changed) pkg agros-keyring-1-1-any.pkg.tar.zst agros-keyring planted ;;
        added) pkg agros-evil-1-1-any.pkg.tar.zst agros-evil ;;
        renamed) pkg zzz-1-1-any.pkg.tar.zst agros-keyring planted ;;
        unreadable) echo junk >"$r/odd-1-1-any.pkg.tar.zst" ;;
        missing) rm "$r/agros-hyprbars-1-1-x86_64.pkg.tar.zst" ;;
        planted) pkg evil-1-1-x86_64.pkg.tar.zst evil ;;
        second) pkg quickshell-git-2-1-x86_64.pkg.tar.zst quickshell-git planted ;;
        misnamed) rm "$r/quickshell-git-1-1-x86_64.pkg.tar.zst" && pkg zzz-1-1-x86_64.pkg.tar.zst quickshell-git ;;
        replaces) pkg quickshell-git-1-1-x86_64.pkg.tar.zst quickshell-git x 'replaces = sudo' ;;
        keyrings) pkg quickshell-git-1-1-x86_64.pkg.tar.zst quickshell-git x '' usr/share/pacman/keyrings/evil.gpg ;;
        settings) pkg quickshell-git-1-1-x86_64.pkg.tar.zst quickshell-git x '' etc/pacman.d/hooks/evil.hook ;;
    esac
    o=$(check) && fail "$c: passed: $o"
    [[ $o == *"!! "* ]] || fail "$c: not said: $o"
done
rm -rf "$r" && cp -r "$t/good" "$r"
o=$(AGROS_OWN_SUMS='' "$here/ci/own-check.sh" "$r" 2>&1) && fail "no sums from the agros job: passed"

# A package aur/packages.txt doesn't list (an AUR dependency) passes once the published database, signed, has it
command -v gpg >/dev/null || { skipped "no gpg"; echo "ok ci-own-check (SKIPPED: no gpg, the published database not tried)"; exit 0; }
export GNUPGHOME=$t/gnupg
mkdir "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
gpg --batch --quiet --armor --export >"$t/key.asc"
mkdir -p "$t/site" "$t/db/libdep-1-1"
printf '%%FILENAME%%\nlibdep-1-1-x86_64.pkg.tar.zst\n\n%%NAME%%\nlibdep\n' >"$t/db/libdep-1-1/desc"
(cd "$t/db" && tar -czf "$t/site/agros.db" libdep-1-1)
gpg --batch --quiet --detach-sign -o "$t/site/agros.db.sig" "$t/site/agros.db"
# (curl: -o's file from $SITE; with -w its HTTP code, 404 when missing; without, a missing one fails, as -f)
stub curl 'w=; while (($#)); do case $1 in -o) o=$2; shift ;; -w) w=1; shift ;; --retry) shift ;; https://*) u=$1 ;; esac; shift; done
f=$SITE/${u#https://pub/}
if [[ -f $f ]]; then cp "$f" "$o"; [[ -z $w ]] || printf 200; elif [[ -n $w ]]; then printf 404; else exit 22; fi'
pub() { SITE=$t/site PATH=$t/bin:$PATH AGROS_PUBLISHED=https://pub AGROS_PUBKEY=$t/key.asc check; }
pkg libdep-1-1-x86_64.pkg.tar.zst libdep
o=$(check) && fail "an AUR dependency neither listed nor published passed: $o"
o=$(pub) || fail "an AUR dependency the published database has refused: $o"
mv "$t/site/agros.db" "$t/site/agros.db.real" && o=$(pub) && fail "an AUR dependency passed, the published database's being none: $o"
mv "$t/site/agros.db.real" "$t/site/agros.db" && echo x >>"$t/site/agros.db.sig"
o=$(pub) && fail "a published database with a bad signature read: $o"
[[ $o == *"couldn't be read or verified"* ]] || fail "a published database with a bad signature not said: $o"
echo "ok ci-own-check"
