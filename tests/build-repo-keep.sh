#!/usr/bin/env bash
# ci/build-repo.sh's own checks, its functions and blocks as it has them, run here: a package already published under
# its version keeps the published file (its signature checked, AgrOS's key alone), unless a compiled one is built
# against another Python (published rebuilt); one of AgrOS's own whose contents changed (a file, a mode, a dependency;
# not the build's time) with its version not raised stops the build, said how to fix it; the published copy not
# readable or not signed by AgrOS's key stops it too; a 404 is a new version. The installer's checksum: the build stops
# when its swaps, patch or pins change under the same calamares_rel. The installer built: each module its settings'
# sequence names in it, or it's taken out (the published one held). curl a stand-in (the published repo in $t/pub)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
b=$here/ci/build-repo.sh
command -v bsdtar >/dev/null || { skipped "no bsdtar"; echo "skip build-repo-keep (no bsdtar)"; exit 0; }
export GNUPGHOME=$t/gnupg
mkdir -m700 "$GNUPGHOME"
for k in agros other; do
    gpg --batch --quiet --passphrase '' --quick-gen-key "$k <$k@agros.invalid>" ed25519 sign never >/dev/null 2>&1
done
keyring=$t/agros.gpg
gpg --batch --quiet --export agros@agros.invalid >"$keyring" 2>/dev/null
# (published.sh's verify_sig, as build-repo.sh sources it; and build-repo.sh's functions)
# shellcheck disable=SC2034  # (read by build-repo.sh's functions)
work=$t/work out=$t/out root=$t/root
mkdir -p "$work" "$out" "$t/pub" "$t/bin" "$root/packages/agros-foo" "$root/packages/agros-bar"
eval "$(sed -n '/^verify_sig() /p; /^stamp=/p' "$here/ci/published.sh")"
sed -n '/^built_against() {$/,/^}$/p; /^contents() {$/,/^}$/p; /^keep_published() {$/,/^}$/p' "$b" >"$t/fns"
# shellcheck disable=SC1091
. "$t/fns"
for f in verify_sig built_against contents keep_published; do declare -F "$f" >/dev/null || fail "$f not found in build-repo.sh"; done
chown() { :; }  # (the builder account, CI's)
echo 'pkgname=agros-foo' >"$root/packages/agros-foo/PKGBUILD"
printf 'pkgname=agros-bar\npkgver() { echo r1; }\n' >"$root/packages/agros-bar/PKGBUILD"
# (the published repo: a file there, 200; none, 404; $CODE: that answer instead. The URL is the last argument. Only
# the current copy asked for, a ?t= query past the CDN's: without one, 000)
cat >"$t/bin/curl" <<C
#!/bin/bash
url=\${*: -1} o= w=
while ((\$#)); do case \$1 in -o) o=\$2; shift ;; -w) w=1 ;; esac; shift; done
[[ \$url == *"?t="[0-9]* ]] || CODE=000
url=\${url%%\?*}
f=$t/pub/\${url##*/} code=\${CODE:-}
[[ -n \$code ]] || { [[ -e \$f ]] && code=200 || code=404; }
[[ \$code == 200 ]] && cp "\$f" "\$o"
if [[ -n \$w ]]; then printf %s "\$code"; else [[ \$code == 200 ]] || exit 22; fi
C
chmod +x "$t/bin/curl"
export PATH=$t/bin:$PATH AGROS_PUBLISHED=https://agros.invalid/x86_64
# pkg <dir> <file> [<line>...]: a package as makepkg makes one (.PKGINFO, .MTREE, its files): "file = <path> <text>", a
# file; "mode = <path> <mode>"; "time = <stamp>", when it was made (touch -d); others go in .PKGINFO
pkg() {
    local d=$1 f=$2 s l p; s=$(mktemp -d); shift 2
    printf 'pkgname = %s\npkgver = 1-1\n' "${f%%-[0-9]*}" >"$s/.PKGINFO"
    for l in "$@"; do
        case $l in
            'file = '*) l=${l#file = }; p=$s/${l%% *}; mkdir -p "${p%/*}"; echo "${l#* }" >"$p" ;;
            'mode = '*) l=${l#mode = }; chmod "${l#* }" "$s/${l%% *}" ;;
            'time = '*) ;;
            *) echo "$l" >>"$s/.PKGINFO" ;;
        esac
    done
    l=$(printf '%s\n' "$@" | sed -n 's/^time = //p')
    find "$s" -exec touch -d "${l:-2026-01-01 00:00}" {} +
    (cd "$s" && bsdtar -czf .MTREE --format=mtree \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' .PKGINFO usr &&
        bsdtar -cf "$d/$f" --zstd .PKGINFO .MTREE usr)
    rm -rf "$s"
    gpg --batch --quiet --yes -u "${SIGNER:-agros}@agros.invalid" --detach-sign "$d/$f" 2>/dev/null
}
keep() { (cd "$out" && keep_published "$1" 2>&1); }
foo=agros-foo-1-1-any.pkg.tar.zst
base=('file = usr/share/agros/a hello' 'depend = bash')
# The same contents, built at another time: the published file and its signature kept
pkg "$t/pub" "$foo" "${base[@]}"
pkg "$out" "$foo" "${base[@]}" 'time = 2026-11-17 12:00'
rm -f "$out/$foo.sig"
o=$(keep "$foo") && [[ $o == *"the published file kept"* ]] && cmp -s "$out/$foo" "$t/pub/$foo" &&
    cmp -s "$out/$foo.sig" "$t/pub/$foo.sig" || fail "an unchanged package not kept as published: $o"
# Changed with its version not raised (a file's text, its mode, a dependency): stopped, said what to raise
for change in 'file = usr/share/agros/a hello!' 'mode = usr/share/agros/a 755' 'depend = zsh'; do
    pkg "$out" "$foo" "${base[@]}" "$change"
    o=$(keep "$foo") && fail "changed ($change) with its version not raised: kept as published"
    [[ $o == *"changed but its version didn't: raise pkgver in packages/agros-foo/PKGBUILD"* ]] ||
        fail "changed ($change) with its version not raised: not said: $o"
done
# ...one versioned by the commits: built from the same commit, so it doesn't build reproducibly
bar=agros-bar-1-1-any.pkg.tar.zst
pkg "$t/pub" "$bar" "${base[@]}"
pkg "$out" "$bar" 'file = usr/share/agros/a other'
o=$(keep "$bar") && fail "a package versioned by the commits, built differently: kept as published"
[[ $o == *"packages/agros-bar doesn't build reproducibly"* ]] || fail "a build that isn't reproducible not said: $o"
# Not published yet: a new version, the build kept as it is
pkg "$out" agros-new-2-1-any.pkg.tar.zst 'file = usr/share/agros/n x'
cp "$out/agros-new-2-1-any.pkg.tar.zst" "$t/new"
keep agros-new-2-1-any.pkg.tar.zst >/dev/null && cmp -s "$out/agros-new-2-1-any.pkg.tar.zst" "$t/new" ||
    fail "a new version not kept as built"
# The published copy unreadable (Pages down), or not signed by AgrOS's key (another key; tampered): stopped
pkg "$out" "$foo" "${base[@]}"
o=$(export CODE=503; keep "$foo") && fail "the published copy unreadable: built over"
[[ $o == *"couldn't be read (HTTP 503)"* ]] || fail "the published copy unreadable: not said: $o"
SIGNER=other pkg "$t/pub" "$foo" "${base[@]}"
o=$(keep "$foo") && fail "a published copy signed by another key kept"
[[ $o == *"signature doesn't check out"* ]] || fail "a published copy signed by another key: not said: $o"
pkg "$t/pub" "$foo" "${base[@]}" && printf x >>"$t/pub/$foo"
keep "$foo" >/dev/null && fail "a tampered published copy kept"
# An AUR package (compiled; not AgrOS's): no contents check, but built against another Python than the published one:
# the rebuild goes out
aur=python-thing-1-1-x86_64.pkg.tar.zst
pkg "$t/pub" "$aur" 'file = usr/lib/python3.11/thing.py a'
pkg "$out" "$aur" 'file = usr/lib/python3.11/thing.py b'
keep "$aur" >/dev/null && cmp -s "$out/$aur" "$t/pub/$aur" || fail "an AUR package unchanged in what it's built against not kept as published"
pkg "$out" "$aur" 'file = usr/lib/python3.12/thing.py a'
cp "$out/$aur" "$t/aur"
o=$(keep "$aur") && cmp -s "$out/$aur" "$t/aur" && [[ $o == *"the rebuild published"* ]] ||
    fail "an AUR package built against another Python: not its rebuild published: $o"

# The installer's checksum: build-repo.sh's own lines (its pins, the swaps it writes, the check), with the patch as it
# is, then changed
awk '/^    calamares_rel=/ { on = 1 } /^    calamares_modules\(\) \{$/ { on = 0 } on' "$b" >"$t/sum"
grep -q 'calamares_sum' "$t/sum" && grep -q "<<'SH'" "$t/sum" || fail "the installer's checksum not found in build-repo.sh"
mkdir -p "$t/croot/ci" "$t/cwork"
cp "$here/ci/calamares-layout.patch" "$t/croot/ci/"
# (asb: fetching CachyOS's recipe fails here, said, and it carries on)
sum() { (root=$t/croot work=$t/cwork; asb() { return 1; }; set -euo pipefail; eval "$(cat "$t/sum")"; echo "checksum ok") 2>&1; }
o=$(sum) && [[ $o == *"checksum ok" ]] || fail "the installer's checksum doesn't match its swaps, patch and pins: $o"
echo '# changed' >>"$t/croot/ci/calamares-layout.patch"
o=$(sum) && fail "the installer's patch changed under the same calamares_rel: not stopped"
[[ $o == *"raise calamares_rel to "* ]] || fail "the installer's patch changed: not said: $o"

# The installer's modules: each its settings' sequence names (a "module@instance" by its module) built in
sed -n '/^    calamares_modules() {$/,/^    }$/p' "$b" >"$t/modules"
# shellcheck disable=SC1091
. "$t/modules"
declare -F calamares_modules >/dev/null || fail "calamares_modules not found in build-repo.sh"
# cal <file> <module>...: a built installer whose settings name welcome, partition, shellprocess@x and users, with
# those modules
cal() {
    local s m; s=$(mktemp -d)
    mkdir -p "$s/etc/calamares"
    printf '%s\n' '---' 'modules-search: [ local ]' 'sequence:' '  - show:' '    - welcome' '  - exec:' '    - partition' \
        '    - shellprocess@x  ' '    - users' '  # - notone' 'branding: agros' '  - notone' >"$s/etc/calamares/settings.conf"
    for m in "${@:2}"; do mkdir -p "$s/usr/lib/calamares/modules/$m" && : >"$s/usr/lib/calamares/modules/$m/module.desc"; done
    (cd "$s" && bsdtar -cf "$1" --zstd etc usr)
    rm -rf "$s"
    : >"$1.sig"
}
cal "$t/cal.pkg.tar.zst" welcome partition shellprocess users
calamares_modules "$t/cal.pkg.tar.zst" >/dev/null && [[ -e $t/cal.pkg.tar.zst ]] || fail "an installer with every module refused"
cal "$t/cal.pkg.tar.zst" welcome partition shellprocess
o=$(calamares_modules "$t/cal.pkg.tar.zst") && fail "an installer without a module its settings name passed"
[[ $o == *"its settings name modules it wasn't built with: users" && ! -e $t/cal.pkg.tar.zst && ! -e $t/cal.pkg.tar.zst.sig ]] ||
    fail "an installer without a module: not said, or not taken out: $o"
echo "ok build-repo-keep"
