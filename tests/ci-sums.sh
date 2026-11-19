#!/usr/bin/env bash
# ci/sums.sh (CI's sign job, before the key): the release signed only as the release job made it, by that job's sums.
# The same files: passes; one changed, one added (hidden too), one gone, a link in place of a file, or no sums at all:
# refused, said. Hidden files left out of the sums made, as upload-artifact leaves them out of the artifact
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
r=$t/out
mkdir -p "$r/x86_64"
for f in a-1-1-any.pkg.tar.zst a-1-1-any.pkg.tar.zst.sig agros.db 'odd name-1-1-any.pkg.tar.zst'; do echo "$f" >"$r/x86_64/$f"; done
echo lock >"$r/x86_64/.agros.db.lck"
sums=$("$here/ci/sums.sh" "$r") || fail "no sums made"
[[ $(grep -c . <<<"$sums") == 4 && $sums != *".agros.db.lck"* && $sums == *" ./x86_64/odd name-1-1-any.pkg.tar.zst"* ]] ||
    fail "not every file's sum, hidden ones left out: $sums"
rm "$r/x86_64/.agros.db.lck"
cp -r "$r" "$t/good"
o=$("$here/ci/sums.sh" "$r" "$sums" 2>&1) || fail "the release as the release job made it refused: $o"
for c in changed added hidden gone link nosums; do
    rm -rf "$r" && cp -r "$t/good" "$r"
    s=$sums
    case $c in
        changed) echo planted >"$r/x86_64/a-1-1-any.pkg.tar.zst" ;;
        added) echo planted >"$r/x86_64/evil-1-1-any.pkg.tar.zst" ;;
        hidden) echo planted >"$r/x86_64/.evil" ;;
        gone) rm "$r/x86_64/a-1-1-any.pkg.tar.zst.sig" ;;
        link) cp "$r/x86_64/agros.db" "$t/db" && ln -sf "$t/db" "$r/x86_64/agros.db" ;;
        nosums) s= ;;
    esac
    o=$("$here/ci/sums.sh" "$r" "$s" 2>&1) && fail "$c: passed: $o"
    [[ $o == *"!! "*"nothing signed"* ]] || fail "$c: not said: $o"
done
echo "ok ci-sums"
