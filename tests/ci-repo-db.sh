#!/usr/bin/env bash
# ci/repo-db.sh (CI's release job, before the sign job): the database made from every package with pacman's repo-add,
# under its plain names (no links), each package's .PKGINFO checked first (ci/pkginfo.sh): one with a line repo-add
# would run as code stops it before repo-add runs, nothing made. Then the database read back: an entry whose name isn't
# its package's (repo-add reading a .PKGINFO another way than pacman), or two packages of one name (one entry over the
# other), stops it. pacman's repo-add itself where there is one (CI), else that part said; a stand-in that lies for the
# read-back
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v bsdtar >/dev/null || { skipped "no bsdtar"; echo "skip ci-repo-db (no bsdtar)"; exit 0; }
r=$t/repo
mkdir "$r"
# pkg <name> <version> [<more .PKGINFO lines>]: <name>-<version>-x86_64.pkg.tar.zst
pkg() {
    local s; s=$(mktemp -d)
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n%s' "$1" "$2" "${3:+$3$'\n'}" >"$s/.PKGINFO"
    echo x >"$s/data"
    (cd "$s" && bsdtar -cf "$r/$1-$2-x86_64.pkg.tar.zst" --zstd .PKGINFO data)
    rm -rf "$s"
}
fresh() {
    rm -rf "$r" && mkdir "$r"
    pkg caelestia-cli 1.0-1 $'pkgdesc = A shell\'s "CLI"\ndepend = python'
    pkg quickshell-git 0.3-1.1 'provides = quickshell'
}
db() { "$here/ci/repo-db.sh" "$r" 2>&1; }

# Refused before repo-add runs (a stand-in that says it ran): nothing made
stub repo-add "touch $t/repo-add-ran"
for c in code nospace link; do
    fresh
    case $c in
        code) pkg evil 1-1 "x[\$({touch,$t/ran})] = 1" ;;
        nospace) pkg caelestia-cli 1.0-1 'pkgname=agros-keyring' ;;
        link) ln -s "$r/caelestia-cli-1.0-1-x86_64.pkg.tar.zst" "$r/link-1-1-any.pkg.tar.zst" ;;
    esac
    o=$(PATH=$t/bin:$PATH db) && fail "$c: made: $o"
    [[ $o == *refused* ]] || fail "$c: not said: $o"
    [[ ! -e $t/repo-add-ran && ! -e $t/ran && ! -e $r/agros.db ]] || fail "$c: repo-add run, or something made: $o"
done

# The read-back: a repo-add that names an entry otherwise than its package (as repo-add read "pkgname=agros-keyring")
# shellcheck disable=SC2016  # (expanded by the stand-in)
stub repo-add 'shift; db=$1; shift; d=$(mktemp -d)
for p; do p=${p#./}; n=${p%%-[0-9]*}; v=${p#"$n-"}; v=${v%-x86_64.pkg.tar.zst}; [[ $n != caelestia-cli ]] || n=${NAME:-$n}
    mkdir "$d/$n-$v" && printf "%%FILENAME%%\n%s\n\n%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%DESC%%\n%%NAME%%\nx\n" "$p" "$n" "$v" >"$d/$n-$v/desc"; done
(cd "$d" && bsdtar -czf - ./*) >"$db"; cp "$db" "${db/.db./.files.}"
ln -sf "$db" "${db%.tar.gz}"; f=${db/.db./.files.}; ln -sf "$f" "${f%.tar.gz}"'
fresh
o=$(PATH=$t/bin:$PATH db) || fail "the stand-in's honest database refused: $o"
[[ -f $r/agros.db && ! -L $r/agros.db && -f $r/agros.files && ! -L $r/agros.files ]] || fail "the database's names left as links"
fresh
o=$(NAME=agros-keyring PATH=$t/bin:$PATH db) && fail "an entry named otherwise than its package passed: $o"
[[ $o == *"doesn't list the packages here"* ]] || fail "an entry named otherwise not said: $o"

# pacman's repo-add itself
rm -f "$t/bin/repo-add"
command -v repo-add >/dev/null || { skipped "no repo-add"; echo "ok ci-repo-db (SKIPPED: no repo-add, pacman's not tried)"; exit 0; }
fresh
o=$(db) || fail "two packages refused: $o"
list=$(bsdtar -tf "$r/agros.db" | LC_ALL=C sort | paste -sd' ')
[[ $list == *"caelestia-cli-1.0-1/desc"* && $list == *"quickshell-git-0.3-1.1/desc"* ]] ||
    fail "the database doesn't list both: $list"
[[ ! -L $r/agros.db && ! -L $r/agros.files ]] || fail "the database's names left as links (Pages serves none)"
# (one name twice: repo-add keeps one entry)
pkg caelestia-cli 1.1-1
o=$(db) && fail "two packages of one name passed: $o"
[[ $o == *"doesn't list the packages here"* ]] || fail "two packages of one name not said: $o"
echo "ok ci-repo-db"
