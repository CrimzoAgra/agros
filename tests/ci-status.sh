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
  "issue list --label status"*) echo 7 ;;
  "issue create"*) for a; do [[ $p == --body-file ]] && cp "$a" %s/body; p=$a; done ;;
esac\n' "$t" "$t" >"$t/bin/gh"
# shellcheck disable=SC2016
printf '#!/bin/bash\ncase "$*" in *agros-approved*) echo "hyprland 0.57.2" ;; *json*) [[ $STATE == *newhypr* ]] && echo "{\\"pkgver\\": \\"0.58.0\\"}" || echo "{\\"pkgver\\": \\"0.57.2\\"}" ;; esac\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
go() { rm -f "$t/gh.log" "$t/body"; STATE=$1 PATH=$t/bin:$PATH GITHUB_REPOSITORY=x/agros OWNER=someone "$here/ci/status.sh" >/dev/null; }
go ""
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "all well not said: $(cat "$t/body")"
grep -qx 'gh issue close 7' "$t/gh.log" || fail "last week's status not closed"
go "ci-failed held sync newhypr"
grep -q '^@someone \*\*Needs a look' "$t/body" || fail "problems not said: $(cat "$t/body")"
for s in "AgrOS's CI: its last run failure (2026-11-19); last good 2026-11-18" "Held back: x (https://h)" \
    "CachyOS ISO changes waiting for a merge: CachyOS: 2 new commit(s) (https://p)" \
    "Hyprland 0.58.0 (Arch's) not approved yet: AgrOS's machines stay on 0.57.2"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
echo "ok ci-status"
