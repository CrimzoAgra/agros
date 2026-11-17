#!/usr/bin/env bash
# ci/published.sh (build-repo.sh): a package that didn't build held back, the published one kept with its signature
# checked, and with the packages of the repo it needs (by name or what they provide), not those built here nor Arch's;
# a tampered copy refused, and so is one signed by another key, even one the keyring the build runs gpg with has (only
# AgrOS's public key counts, $keyring); none published: the build fails. A published repo here (file://), signed with a
# key of the test's own
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export GNUPGHOME=$t/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'AgrOS test <test@agros.invalid>' default sign never >/dev/null 2>&1
key=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
# (AgrOS's public key alone, as build-repo.sh makes it from ci/agros.asc; and another key in gpg's own keyring)
keyring=$t/agros.gpg
gpg --batch --quiet --export "$key" >"$keyring" 2>/dev/null
gpg --batch --quiet --passphrase '' --quick-gen-key 'Not AgrOS <other@agros.invalid>' default sign never >/dev/null 2>&1
other=$(gpg --list-secret-keys --with-colons other@agros.invalid 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
pub=$t/pub out=$t/out work=$t/work
mkdir -p "$pub" "$out" "$work"
# pkg <dir> <name> <version> [<line>...]: a package (its .PKGINFO; "installed = " and "pkgbuild_sha256sum = " lines: its
# .BUILDINFO; "file = <path>": a file in it, a program (true's copy) under usr/bin), signed
pkg() {
    local d=$1 n=$2 v=$3 s p; s=$(mktemp -d); shift 3
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$n" "$v" >"$s/.PKGINFO"
    printf '%s\n' "$@" | grep -Ev '^(installed|pkgbuild_sha256sum|file) = |^$' >>"$s/.PKGINFO" || true
    printf '%s\n' "$@" | grep -E '^(installed|pkgbuild_sha256sum) = ' >"$s/.BUILDINFO" || true
    for p in "$@"; do
        [[ $p == 'file = '* ]] || continue
        p=$s/${p#file = } && mkdir -p "${p%/*}"
        if [[ $p == */usr/bin/* ]]; then cp "$(type -P true)" "$p"; else : >"$p"; fi
    done
    # shellcheck disable=SC2046  # (no .BUILDINFO, no files: not in the package)
    bsdtar -cf "$d/$n-$v-x86_64.pkg.tar.zst" --zstd -C "$s" .PKGINFO $([[ -s $s/.BUILDINFO ]] && echo .BUILDINFO) \
        $([[ -d $s/usr ]] && echo usr)
    gpg --batch --quiet -u "${SIGNER:-$key}" --detach-sign "$d/$n-$v-x86_64.pkg.tar.zst" 2>/dev/null
    rm -rf "$s"
}
pkg "$pub" app 1-1 'depend = libx>=2' 'depend = glibc' 'depend = built-dep'
pkg "$pub" libx 2-1 'depend = libdeep'
pkg "$pub" libdeep 1-1
pkg "$pub" built-dep 1-1
pkg "$pub" quickshell-git 0.3-1.1 'provides = quickshell=0.3'
pkg "$pub" lonely 1-1
SIGNER=$other pkg "$pub" stranger 1-1
# (for reused: heavy, built from $t/heavy/PKGBUILD with libq 5-1: a program that needs libc.so.6, a Python 3.11 module)
mkdir -p "$t/heavy" && echo 'pkgname=heavy' >"$t/heavy/PKGBUILD"
pkg "$pub" heavy 2-1 'depend = libq>=5' 'installed = libq-5-1-x86_64' 'file = usr/bin/heavy' \
    'file = usr/lib/python3.11/heavy.py' "pkgbuild_sha256sum = $(sha256sum <"$t/heavy/PKGBUILD" | cut -d' ' -f1)"
# (one that provides more than a pipe holds: found by its name all the same, published or here. Under pipefail a
# grep -q stopping at the name failed the search, its provides cut off: quickshell-git and Calamares never found)
mapfile -t many < <(seq -f 'provides = p%g' 1 20000)
pkg "$pub" bigprov 1-1 "${many[@]}"
repo-add -q "$pub/agros.db.tar.gz" "$pub"/*.pkg.tar.zst 2>/dev/null
cp --remove-destination "$pub/agros.db.tar.gz" "$pub/agros.db"
gpg --batch --quiet -u "$key" --detach-sign "$pub/agros.db"
# (built here: a newer built-dep)
pkg "$out" built-dep 2-1
export AGROS_PUBLISHED=file://$pub
# (curl itself, but only the current copy asked for, a ?t= query past Pages' CDN's: without one, a failure)
real=$(type -P curl)
mkdir "$t/curl"
printf '#!/bin/bash\nfor a; do [[ $a != file://* || $a == *"?t="[0-9]* ]] || exit 22; done\nexec %q "$@"\n' "$real" >"$t/curl/curl"
chmod +x "$t/curl/curl"
export PATH=$t/curl:$PATH
asb() { "$@"; }
chown() { :; }  # (the builder account, CI's)
held=()
# shellcheck source=../ci/published.sh
. "$here/ci/published.sh"
pub_db >/dev/null && pub_desc bigprov >/dev/null || fail "a published package that provides much not found by its name"
mkdir -p "$t/o2" && cp "$pub"/bigprov-1-1-x86_64.pkg.tar.zst "$t/o2/"
(out=$t/o2; out_has bigprov) || fail "a package here that provides much not found by its name"
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
# ...and one signed by another key (one gpg itself would call good: it has that key)
gpg --batch --verify "$pub/stranger-1-1-x86_64.pkg.tar.zst.sig" "$pub/stranger-1-1-x86_64.pkg.tar.zst" 2>/dev/null || fail "test setup: the other key's signature not good to gpg"
carry_over stranger >/dev/null && fail "a published package signed by another key kept"
[[ ! -e $out/stranger-1-1-x86_64.pkg.tar.zst ]] || fail "a published package signed by another key left in the repo"
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
# reused: the published package kept, not built, unless its rebuild would go out: its version or PKGBUILD changed, a
# library it needs gone from the repos, another Python (makepkg and pacman stand-ins: the version $REL gives, the
# library $GONE not in any repo's file list, the repos' Python at $PY)
mkdir -p "$t/bin"
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" = --printsrcinfo ] && printf "pkgbase = heavy\\n\\tpkgver = 2\\n\\tpkgrel = %%s\\n\\npkgname = heavy\\n" "${REL:-1}"\nexit 0\n' >"$t/bin/makepkg"
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$1" in\n-Fy) exit 0 ;;\n-Fq) [ "$2" = "${GONE:-}" ] && exit 1; echo core/some ;;\n-Sp) [ "$4" = python ] && echo "${PY:-3.11.9-1}" ;;\nesac\n' >"$t/bin/pacman"
chmod +x "$t/bin/"*
heavy() { rm -f "$out"/heavy-*; (PATH=$t/bin:$PATH; reused "$t/heavy") >/dev/null; }
heavy && [[ -e $out/heavy-2-1-x86_64.pkg.tar.zst && -e $out/heavy-2-1-x86_64.pkg.tar.zst.sig ]] ||
    fail "an unchanged package not kept as published"
# (a newer libq alone: its rebuild would be thrown away, built_against the same, so not built: caelestia-shell and
# Calamares were, every run)
LIBQ=6-1 heavy || fail "built though only a dependency's version changed"
readelf -d "$(type -P true)" | grep 'NEEDED.*libc.so.6' >/dev/null || fail "test setup: true doesn't need libc.so.6"
GONE=libc.so.6 heavy && fail "kept though a library it needs is gone"
PY=3.12.1-1 heavy && fail "kept though Python changed"
REL=2 heavy && fail "kept though its version changed"
echo 'pkgname=heavy # new' >"$t/heavy/PKGBUILD"
heavy && fail "kept though its PKGBUILD changed"
[[ ! -e $out/heavy-2-1-x86_64.pkg.tar.zst ]] || fail "a package to build left in the repo as published"
echo "ok build-repo-hold"
