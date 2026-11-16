#!/usr/bin/env bash
# ci/published.sh (build-repo.sh): a package that didn't build held back, the published one kept with its signature
# checked, and with the packages of the repo it needs (by name or what they provide), not those built here nor Arch's;
# a tampered copy refused; none published: the build fails. A published repo here (file://), signed with a key of the
# test's own
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export GNUPGHOME=$t/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
export key; key=$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')
pub=$t/pub out=$t/out work=$t/work
mkdir -p "$pub" "$out" "$work"
# pkg <dir> <name> <version> [<line>...]: a package (its .PKGINFO), signed
pkg() {
    local d=$1 n=$2 v=$3 s; s=$(mktemp -d); shift 3
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$n" "$v" >"$s/.PKGINFO"
    (($#)) && printf '%s\n' "$@" >>"$s/.PKGINFO"
    bsdtar -cf "$d/$n-$v-x86_64.pkg.tar.zst" --zstd -C "$s" .PKGINFO
    gpg --batch --quiet --detach-sign "$d/$n-$v-x86_64.pkg.tar.zst" 2>/dev/null
    rm -rf "$s"
}
pkg "$pub" app 1-1 'depend = libx>=2' 'depend = glibc' 'depend = built-dep'
pkg "$pub" libx 2-1 'depend = libdeep'
pkg "$pub" libdeep 1-1
pkg "$pub" built-dep 1-1
pkg "$pub" quickshell-git 0.3-1.1 'provides = quickshell=0.3'
pkg "$pub" lonely 1-1
repo-add -q "$pub/agros.db.tar.gz" "$pub"/*.pkg.tar.zst 2>/dev/null
cp --remove-destination "$pub/agros.db.tar.gz" "$pub/agros.db"
gpg --batch --quiet --detach-sign "$pub/agros.db"
# (built here: a newer built-dep)
pkg "$out" built-dep 2-1
export AGROS_PUBLISHED=file://$pub
asb() { "$@"; }
chown() { :; }  # (the builder account, CI's)
held=()
# shellcheck source=../ci/published.sh
. "$here/ci/published.sh"
carry_over app >/dev/null || fail "a held package not kept from the published repo"
got=$(cd "$out" && ls ./*.pkg.tar.zst | sed 's|^\./||' | paste -sd' ')
[[ $got == "app-1-1-x86_64.pkg.tar.zst built-dep-2-1-x86_64.pkg.tar.zst libdeep-1-1-x86_64.pkg.tar.zst libx-2-1-x86_64.pkg.tar.zst" ]] ||
    fail "not the held package with the repo's packages it needs (and not the one built here): $got"
for f in app libx libdeep; do [[ -s $(ls "$out/$f"-*.sig) ]] || fail "$f kept without its signature"; done
carry_over quickshell >/dev/null && [[ -e $out/quickshell-git-0.3-1.1-x86_64.pkg.tar.zst ]] ||
    fail "a package found by what it provides not kept"
# A published copy that doesn't match its signature: refused, not left in the repo
printf 'x' >>"$pub/lonely-1-1-x86_64.pkg.tar.zst"
carry_over lonely >/dev/null && fail "a tampered published package kept"
[[ ! -e $out/lonely-1-1-x86_64.pkg.tar.zst ]] || fail "a tampered published package left in the repo"
# hold: said ("<name>: <why>"); none published: the build stops
grep -qx "app: it didn't build" <<<"$(hold app "it didn't build" >/dev/null; printf '%s\n' "${held[@]}")" ||
    fail "a hold not said: $(hold app x 2>&1)"
(hold nosuch "it didn't build" >/dev/null) && fail "a package with none published to keep didn't stop the build"
# hold_new (the tests found this run's new AUR builds broke them): each new build swapped for the published one, the
# published files and AgrOS's own left as they are, one never published left out
rm -f "$out"/*
cp "$pub/libdeep-1-1-x86_64.pkg.tar.zst"* "$out/"  # (kept as published by the build)
pkg "$out" libx 3-1 'depend = libdeep'
pkg "$out" agros-system r9-1
pkg "$out" brand-new 1-1
held=()
hold_new "broke the tests" >/dev/null
got=$(cd "$out" && ls ./*.pkg.tar.zst | sed 's|^\./||' | paste -sd' ')
[[ $got == "agros-system-r9-1-x86_64.pkg.tar.zst libdeep-1-1-x86_64.pkg.tar.zst libx-2-1-x86_64.pkg.tar.zst" ]] ||
    fail "this run's new builds not swapped for the published ones: $got"
[[ $(printf '%s\n' "${held[@]}" | sort | paste -sd,) == "brand-new: broke the tests,libx: broke the tests" ]] ||
    fail "the held ones not said: ${held[*]}"
echo "ok build-repo-hold"
