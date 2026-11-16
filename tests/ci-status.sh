#!/usr/bin/env bash
# ci/status.sh: the weekly issue says nothing broke when all is well, and lists what needs a look otherwise (a failed
# run, a held issue, CachyOS changes waiting, a Hyprland not approved); last week's closed, the owner mentioned. gh and
# curl are stand-ins, their answers as $STATE says
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "gh $*" >>%s/gh.log
case "$*" in
  "run list -R x/agros "*) [[ $STATE == *ci-failed* ]] && echo failure && echo 2026-11-19 || { echo success; echo 2026-11-20; }; echo 2026-11-18 ;;
  "run list -R "*) echo success; echo 2026-11-20; echo 2026-11-20 ;;
  "issue list --label held"*) [[ $STATE == *held* ]] && echo "Held back: x (https://h)"; true ;;
  "pr list"*) [[ $STATE == *sync* ]] && echo "CachyOS: 2 new commit(s) (https://p)"; true ;;
  "issue list --label status --state all"*) cat %s/lastbody 2>/dev/null; true ;;
  "issue list --label status"*) echo 7 ;;
  "issue create"*) for a; do [[ $p == --body-file ]] && cp "$a" %s/body; p=$a; done ;;
esac\n' "$t" "$t" "$t" >"$t/bin/gh"
# shellcheck disable=SC2016
printf '#!/bin/bash\ncase "$*" in *agros-approved*) echo "hyprland 0.57.2" ;; *json*) [[ $STATE == *newhypr* ]] && echo "{\\"pkgver\\": \\"0.58.0\\"}" || echo "{\\"pkgver\\": \\"0.57.2\\"}" ;; esac\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
# (the size watch's out dir: what it found, its table rows, its baseline)
mkdir -p "$t/sizes"
echo '| The ISO: its packages | 3, 68 MiB installed |' >"$t/sizes/table"
printf '%s\n' 'iso hyprland 66560' 'inst cairo 1536' >"$t/sizes/baseline"
: >"$t/sizes/report"
go() { rm -f "$t/gh.log" "$t/body"; STATE=$1 PATH=$t/bin:$PATH GITHUB_REPOSITORY=x/agros OWNER=someone SIZES=${SIZES-$t/sizes} "$here/ci/status.sh" >/dev/null; }
last_sizes() { PATH=$t/bin:$PATH "$here/ci/status.sh" --last-sizes; }
go ""
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "all well not said: $(cat "$t/body")"
grep -qx 'gh issue close 7' "$t/gh.log" || fail "last week's status not closed"
grep -qxF '| The ISO: its packages | 3, 68 MiB installed |' "$t/body" || fail "the size watch's row not in the table: $(cat "$t/body")"
# (the baseline in the body, unseen, and read back by --last-sizes as it was)
cp "$t/body" "$t/lastbody"
[[ $(last_sizes) == $'iso hyprland 66560\ninst cairo 1536' ]] || fail "the baseline not read back: $(last_sizes)"
# (what the size watch found needs a look)
echo 'The ISO: libplasma (40 MiB) is new this week, pulled in by qtengine' >"$t/sizes/report"
go ""
grep -qxF -- '- The ISO: libplasma (40 MiB) is new this week, pulled in by qtengine' "$t/body" ||
    fail "the size watch's find not said: $(cat "$t/body")"
: >"$t/sizes/report"
# (it not having run: said, and last week's baseline kept for next week)
SIZES='' go ""
grep -qF -- "- The size watch didn't run" "$t/body" || fail "the size watch not running not said: $(cat "$t/body")"
cp "$t/body" "$t/lastbody"
[[ $(last_sizes) == $'iso hyprland 66560\ninst cairo 1536' ]] || fail "last week's baseline not kept: $(last_sizes)"
go "ci-failed held sync newhypr"
grep -q '^@someone \*\*Needs a look' "$t/body" || fail "problems not said: $(cat "$t/body")"
for s in "AgrOS's CI: its last run failure (2026-11-19); last good 2026-11-18" "Held back: x (https://h)" \
    "CachyOS ISO changes waiting for a merge: CachyOS: 2 new commit(s) (https://p)" \
    "Hyprland 0.58.0 (Arch's) not approved yet: AgrOS's machines stay on 0.57.2"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
echo "ok ci-status"
