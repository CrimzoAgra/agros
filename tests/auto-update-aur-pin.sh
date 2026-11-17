#!/usr/bin/env bash
# agros-system's auto-update-aur --fetch with a version (<base>=<version>: a rebuild for a new runtime of one [agros]
# publishes), on a fake AUR (git repos of build files, git's own clone of them): the version installed made, not the
# AUR's newest. Caelestia's: the newest commit of its build files whose .SRCINFO has that version (pkgver and pkgrel),
# their whole history fetched for it. Quickshell's, a git package: its git source pinned at the commit its version ends
# with (#commit=, a #branch= replaced), AgrOS's fix still added. None found (a version the AUR never had, not one git
# source): exit 3, nothing fetched or built. Without a version: the AUR's newest, as before
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/aur" "$t/home"
sed -e "s|/usr/lib/agros/auto-update-aur|$t/auto-update-aur|g" "$here/packages/agros-system/auto-update-aur" >"$t/auto-update-aur"
chmod +x "$t/auto-update-aur"
# (AgrOS's fixes for AUR packages beside it, as installed: aur-agros-patch, aur-patches/)
cp -r "$here/packages/agros-system/aur-agros-patch" "$here/packages/agros-system/aur-patches" "$t/"
stub gpg 'true'
# makepkg: the source array as it reads it (--printsrcinfo), and the version and sources it fetches (--verifysource,
# noted)
# shellcheck disable=SC2016  # (the stand-in's)
stub makepkg 'case " $* " in
    *" --printsrcinfo "*) bash -c '"'"'. ./PKGBUILD; echo "pkgbase = $pkgname"; for s in "${source[@]}"; do printf "\tsource = %s\n" "$s"; done'"'"' ;;
    *" --verifysource "*) bash -c '"'"'. ./PKGBUILD; echo "verify ${PWD##*/} $pkgver-$pkgrel ${source[*]}"'"'"' >>'"$t"'/calls ;;
esac'
export PATH=$t/bin:$PATH HOME=$t/home
# The AUR's address, its fake's: git's own clone of the repos below (their files as written: no CRLF)
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.file://$t/aur/.insteadOf" GIT_CONFIG_VALUE_0=https://aur.archlinux.org/ \
    GIT_CONFIG_KEY_1=core.autocrlf GIT_CONFIG_VALUE_1=false
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# commit <base> <pkgver> <pkgrel> [<source line>...]: a commit of its build files (PKGBUILD and .SRCINFO alike)
commit() {
    local n=$1 v=$2 rel=$3 r=$t/aur/$1.git
    shift 3
    [[ -d $r ]] || git init -q -b master "$r"
    printf '_pkgname=%s\npkgname=%s\npkgver=%s\npkgrel=%s\nurl=https://example.invalid/%s\n' "${n%-git}" "$n" "$v" "$rel" "$n" >"$r/PKGBUILD"
    printf '%s\n' "${@:-source=(a.tar.gz)}" >>"$r/PKGBUILD"
    (cd "$r" && { printf 'pkgbase = %s\n\tpkgver = %s\n\tpkgrel = %s\n' "$n" "$v" "$rel"; makepkg --printsrcinfo | grep source; } >.SRCINFO &&
        git add -A && git commit -qm "$v-$rel")
}
fetch() { (cd "$t" && "$t/auto-update-aur" --fetch "$t/build" "$@"); }
calls() { cat "$t/calls" 2>/dev/null; rm -f "$t/calls"; }

# Caelestia: 1.0-1, 1.1-1, 1.1-2, then 1.2-1 (the AUR's newest). Installed 1.1-1: that one's build files
for v in 1.0-1 1.1-1 1.1-2 1.2-1; do commit caelestia-shell "${v%-*}" "${v#*-}"; done
fetch caelestia-shell=1.1-1 >"$t/out" 2>&1 || fail "caelestia-shell at 1.1-1 not fetched: $(cat "$t/out")"
[[ $(calls) == "verify caelestia-shell 1.1-1 a.tar.gz" ]] || fail "caelestia-shell's build files not the version installed's"
# One AgrOS adds its fix to (its pkgrel .2 after the AUR's): the AUR's own version found, the fix added
commit patched 2.0 1 && commit patched 2.1 1
echo '(a fix)' >"$t/aur-patches/patched.patch"
fetch patched=2.0-1.2 >"$t/out" 2>&1 && [[ $(calls) == "verify patched 2.0-1.2 a.tar.gz" ]] ||
    fail "a base with AgrOS's fix not found at its AUR version: $(cat "$t/out")"
# (the pkgrel too: 1.1-2's, not 1.1-1's)
rm -rf "$t/build"
fetch caelestia-shell=1.1-2 >"$t/out" 2>&1 && [[ $(calls) == "verify caelestia-shell 1.1-2 a.tar.gz" ]] ||
    fail "caelestia-shell at 1.1-2: $(cat "$t/out")"
# A version the AUR's build files never had (or another epoch): exit 3, said, nothing fetched
for v in 1.5-1 2:1.1-1; do
    rm -rf "$t/build"
    rc=0; fetch "caelestia-shell=$v" >"$t/out" 2>&1 || rc=$?
    [[ $rc == 3 && $(cat "$t/out") == *"caelestia-shell: the AUR has no build files of the version installed, $v"* && -z $(calls) ]] ||
        fail "caelestia-shell at $v, not on the AUR: exit $rc, $(cat "$t/out")"
done
# No version: the AUR's newest, its last commit alone
rm -rf "$t/build"
fetch caelestia-shell >"$t/out" 2>&1 && [[ $(calls) == "verify caelestia-shell 1.2-1 a.tar.gz" ]] ||
    fail "caelestia-shell without a version not the AUR's newest: $(cat "$t/out")"
[[ $(git -C "$t/build/caelestia-shell" rev-list --count HEAD) == 1 ]] || fail "the AUR's newest fetched with its whole history"

# Quickshell, a git package (AgrOS's fix, pkgrel .2): its git source pinned at the installed version's commit, a
# #branch= replaced; the AUR's build files as they are, AgrOS's fix added after
# shellcheck disable=SC2016  # (the PKGBUILD's)
commit quickshell-git 0.3.0.r0.g59e9c47 1 'source=("$_pkgname"::"git+$url.git#branch=master"' '  quickshell-check.hook)'
rm -rf "$t/build"
fetch quickshell-git=0.3.0.r5.gabc1234-1.2 >"$t/out" 2>&1 || fail "quickshell-git at its version installed not fetched: $(cat "$t/out")"
[[ $(calls) == "verify quickshell-git 0.3.0.r0.g59e9c47-1.2 quickshell::git+https://example.invalid/quickshell-git.git#commit=abc1234 quickshell-check.hook" ]] ||
    fail "quickshell-git's source not pinned at abc1234, or AgrOS's fix not added: $(cat "$t/out")"
# Two git sources, or none: which to pin isn't known: exit 3, nothing fetched
# shellcheck disable=SC2016
commit quickshell-git 0.3.0.r0.g59e9c47 1 'source=("git+$url.git" "git+https://example.invalid/other.git")'
rm -rf "$t/build"
rc=0; fetch quickshell-git=0.3.0.r5.gabc1234-1.2 >"$t/out" 2>&1 || rc=$?
[[ $rc == 3 && $(cat "$t/out") == *"quickshell-git: not one git source to pin at abc1234"* && -z $(calls) ]] ||
    fail "quickshell-git with two git sources: exit $rc, $(cat "$t/out")"
echo "ok auto-update-aur-pin"
