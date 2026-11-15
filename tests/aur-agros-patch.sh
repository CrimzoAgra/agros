#!/usr/bin/env bash
# aur-agros-patch: AgrOS's fix for an AUR package added to its build files (a prepare() applying it to the sources, the
# pkgrel a ".1" above), nothing for a package with none, a PKGBUILD that no longer fits refused; and the patch AgrOS
# ships (Quickshell's) one that applies that way: paths from the sources' folder
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/lib/aur-patches"
cp "$here/packages/agros-system/aur-agros-patch" "$t/lib/"
printf -- '--- a/demo/f\n+++ b/demo/f\n@@ -1 +1 @@\n-old\n+new\n' >"$t/lib/aur-patches/demo.patch"
mk() { rm -rf "${t:?}/${1:?}"; mkdir -p "$t/$1"; printf '%s\n' "$2" >"$t/$1/PKGBUILD"; }
mk demo $'pkgname=demo\npkgver=1\npkgrel=3\nbuild() { :; }'
"$t/lib/aur-agros-patch" "$t/demo" demo || fail "a package with a fix: refused"
grep -qx 'pkgrel=3.1' "$t/demo/PKGBUILD" || fail "its pkgrel not a .1 above the AUR's: $(grep pkgrel "$t/demo/PKGBUILD")"
# (its prepare() run as makepkg would: the sources in srcdir, the build files in startdir)
mkdir -p "$t/src/demo" && echo old >"$t/src/demo/f"
(export srcdir=$t/src startdir=$t/demo; . "$t/demo/PKGBUILD"; prepare >/dev/null) || fail "its prepare() didn't apply the fix"
[[ $(cat "$t/src/demo/f") == new ]] || fail "the fix not in its sources"
# (a patch that no longer fits: the build fails)
echo other >"$t/src/demo/f"
(export srcdir=$t/src startdir=$t/demo; . "$t/demo/PKGBUILD"; prepare >/dev/null 2>&1) && fail "a patch that no longer applies didn't fail the build"
mk plain $'pkgname=plain\npkgrel=1'
"$t/lib/aur-agros-patch" "$t/plain" plain && grep -qx 'pkgrel=1' "$t/plain/PKGBUILD" && ! grep -q prepare "$t/plain/PKGBUILD" ||
    fail "a package with no fix changed"
mk demo $'pkgname=demo\npkgrel=1.2'
"$t/lib/aur-agros-patch" "$t/demo" demo 2>/dev/null && fail "a dotted pkgrel taken"
mk demo $'pkgname=demo\npkgrel=1\nprepare() { :; }'
"$t/lib/aur-agros-patch" "$t/demo" demo 2>/dev/null && fail "a PKGBUILD's own prepare() replaced"
# Each patch shipped: for a package CI builds or the boot rebuilds (its paths a/<folder>/..., from srcdir)
for p in "$here"/packages/agros-system/aur-patches/*.patch; do
    grep -q '^--- a/[^/]*/' "$p" && grep -q '^+++ b/[^/]*/' "$p" || fail "${p##*/}: its paths not from the sources' folder"
done
grep -q 'aur-agros-patch' "$here/ci/build-repo.sh" && ! grep -qx 'aur/quickshell-git' "$here/aur/packages.txt" ||
    fail "CI builds Quickshell from the AUR without AgrOS's fix"
echo "ok aur-agros-patch"
