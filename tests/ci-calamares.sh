#!/usr/bin/env bash
# ci/build-repo.sh's Calamares: the checksum recorded for calamares_rel is that of its swaps, patch and pins (one changed
# with calamares_rel not raised fails here, before CI's long AUR builds reach it), and at the pinned commits the recipe
# still has the lines its seds edit and the swaps and patch fit the installer's code; a line they no longer find fails
# them (their checks), not an installer without them
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
b=$here/ci/build-repo.sh
var() { sed -n "/^ *$1=/{s///p;q;}" "$b"; }
rel=$(var calamares_rel) pin=$(var calamares_pkgbuild) src=$(var calamares_src)
[[ $rel =~ ^[0-9]+$ && $pin =~ ^[0-9a-f]{40}$ && $src =~ ^[0-9a-f]{40}$ ]] ||
    fail "calamares_rel or the pins not found in build-repo.sh: '$rel' '$pin' '$src'"
recorded=$(sed -n "s/^ *$rel) calamares_sum=\([0-9a-f]*\) ;;\$/\1/p" "$b")
# (the swaps as build-repo.sh writes them: its <<'SH' block)
awk "/<<'SH'\$/ { on = 1; next } /^SH\$/ { on = 0 } on" "$b" >"$t/calamares-labels"
grep -q 'calamares-layout.patch' "$t/calamares-labels" || fail "the swaps (build-repo.sh's <<'SH' block) not found"
sum=$(printf '%s\n' "$pin" "$src" | cat - "$t/calamares-labels" "$here/ci/calamares-layout.patch" | sha256sum | cut -c1-12)
[[ $sum == "$recorded" ]] ||
    fail "the Calamares swaps or pins changed under calamares_rel $rel (its checksum ${recorded:-none}): raise it, its line's checksum $sum"

# The recipe and the code at the pins
if ! curl -fsSL --retry 3 -m 60 -o "$t/PKGBUILD" \
    "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/$pin/cachyos-calamares/PKGBUILD" 2>/dev/null ||
    ! git init -q "$t/cal" || ! git -C "$t/cal" sparse-checkout set src/modules ||
    ! git -C "$t/cal" fetch -q --depth 1 --filter=blob:none https://github.com/CachyOS/cachyos-calamares.git "$src" 2>/dev/null ||
    ! git -C "$t/cal" checkout -q FETCH_HEAD 2>/dev/null; then
    skipped "CachyOS's installer recipe or code couldn't be fetched"
    echo "ok ci-calamares (SKIPPED: CachyOS's installer recipe or code couldn't be fetched)"
    exit 0
fi
# (build-repo.sh's seds: its pkgrel a plain number, its source the cachyos branch, prepare()'s first line the cd into
# the code, after which the swaps go)
grep -qx 'pkgrel=[0-9][0-9]*' "$t/PKGBUILD" || fail "the recipe's pkgrel isn't a plain number"
# shellcheck disable=SC2016  # (the recipe's own variable)
grep -qxF 'source=(calamares::"git+${url}.git#branch=cachyos")' "$t/PKGBUILD" || fail "the recipe's source isn't the cachyos branch"
[[ $(sed -n '/^prepare() {$/{n;p;q}' "$t/PKGBUILD") =~ ^[[:space:]]*cd\ \"?\$\{?srcdir\}?/calamares\"?$ ]] ||
    fail "the recipe's prepare() doesn't start with the cd into the code"
# prepare() as makepkg runs it (errexit on), in the code, with the patch beside the recipe
mkdir "$t/start" && cp "$here/ci/calamares-layout.patch" "$t/start/"
{ echo 'prepare() {'; cat "$t/calamares-labels"; echo '}'; echo prepare; } >"$t/prepare"
prep() { (cd "$t/cal" && startdir=$t/start bash -e "$t/prepare" 2>&1); }
out=$(prep) || fail "AgrOS's changes don't fit the installer's code at $src: $(tail -n1 <<<"$out")"
# (each check bites: a line that moved, one of the EFI size's three gone)
undo() { git -C "$t/cal" checkout -q -- . && git -C "$t/cal" clean -qfd; }
undo
sed -i 's/gs->value( "packagechooser_bootloader" )/gs->value( "packagechooser_loader" )/' "$t/cal/src/modules/zfs/ZfsJob.cpp"
out=$(prep) && fail "a bootloader line that moved passed"
[[ $out == *"AgrOS's changes to Calamares no longer fit"* ]] || fail "a bootloader line that moved not said: $out"
undo
sed -i '0,/isEfiFilesystemRecommendedSize( efiPartition )/s//isEfiFilesystemRecommendedSize( esp )/' \
    "$t/cal/src/modules/partition/gui/ChoicePage.cpp"
out=$(prep) && fail "an EFI size check left out passed"
[[ $out == *"AgrOS's changes to Calamares no longer fit"* ]] || fail "an EFI size check left out not said: $out"
echo "ok ci-calamares"
