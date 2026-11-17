#!/usr/bin/env bash
# ci/own-check.sh (CI's release, before it signs): AgrOS's own packages exactly those the agros job built, by their sums
# (that job's output): one changed, one added (by its file's name or only by its .PKGINFO's: agros-keyring under
# another file name), one not readable, or one of the agros job's missing, and nothing is signed; the AUR's packages
# not its business. No sums: refused
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v bsdtar >/dev/null || { skipped "no bsdtar"; echo "skip ci-own-check (no bsdtar)"; exit 0; }
r=$t/repo
mkdir "$r"
# pkg <file> <name> [<text>]: a package of that name
pkg() {
    local s; s=$(mktemp -d)
    printf 'pkgname = %s\npkgver = 1-1\n' "$2" >"$s/.PKGINFO" && echo "${3:-x}" >"$s/data"
    (cd "$s" && bsdtar -cf "$r/$1" --zstd .PKGINFO data)
    rm -rf "$s"
}
pkg agros-keyring-1-1-any.pkg.tar.zst agros-keyring
pkg agros-hyprbars-1-1-x86_64.pkg.tar.zst agros-hyprbars && echo sig >"$r/agros-hyprbars-1-1-x86_64.pkg.tar.zst.sig"
sums=$(cd "$r" && sha256sum agros-keyring-1-1-any.pkg.tar.zst && sha256sum -b agros-hyprbars-1-1-x86_64.pkg.tar.zst)
pkg quickshell-git-1-1-x86_64.pkg.tar.zst quickshell-git
cp -r "$r" "$t/good"
check() { AGROS_OWN_SUMS=$sums "$here/ci/own-check.sh" "$r" 2>&1; }
o=$(check) || fail "AgrOS's own packages as built refused: $o"
# (each case on the good repo again)
for c in changed added renamed unreadable missing; do
    rm -rf "$r" && cp -r "$t/good" "$r"
    case $c in
        changed) pkg agros-keyring-1-1-any.pkg.tar.zst agros-keyring planted ;;
        added) pkg agros-evil-1-1-any.pkg.tar.zst agros-evil ;;
        renamed) pkg zzz-1-1-any.pkg.tar.zst agros-keyring planted ;;
        unreadable) echo junk >"$r/odd-1-1-any.pkg.tar.zst" ;;
        missing) rm "$r/agros-hyprbars-1-1-x86_64.pkg.tar.zst" ;;
    esac
    o=$(check) && fail "$c: passed: $o"
    [[ $o == *"!! "* ]] || fail "$c: not said: $o"
done
rm -rf "$r" && cp -r "$t/good" "$r"
o=$(AGROS_OWN_SUMS='' "$here/ci/own-check.sh" "$r" 2>&1) && fail "no sums from the agros job: passed"
echo "ok ci-own-check"
