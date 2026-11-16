#!/usr/bin/env bash
# CI's word on a run, as one GitHub issue (label "held"): opened, or brought up to date, when something was held back
# or nothing went out; closed, said why, once a run puts everything out again. GitHub notifies of each (the repo's
# watchers: its owner). From the report job, gh with GH_TOKEN (issues: write). Environment:
#   RESULT   the tests' (ci/test-passes.sh): ok, hold-agros, hold-upstream, fail; empty: they didn't run
#   BUILD    the build job's result (success, failure...); RELEASE the release job's
#   HELD     a file: what was held back, "<name>: <why>" each (build-repo.sh's AGROS_HELD)
#   REPORT   a file: the tests' report (test-passes.sh's AGROS_TEST_REPORT)
#   RUN_URL  this run's page
set -uo pipefail
shopt -s extglob
held=$(cat "${HELD:-/dev/null}" 2>/dev/null)
report=$(cat "${REPORT:-/dev/null}" 2>/dev/null)
case ${BUILD:-}/${RESULT:-} in
    success/ok) state=ok ;;
    success/hold-agros) state="this run's new AUR builds broke AgrOS's tests: the published ones kept" ;;
    success/hold-upstream) state="an Arch update broke AgrOS's tests: its Hyprland not approved, the new AUR builds held back" ;;
    success/fail) state="AgrOS's own code fails its tests: nothing published" ;;
    success/) state="the tests didn't run to the end (a step before them failed): nothing published" ;;
    *) state="the repo didn't build (${BUILD:-not run}): nothing published" ;;
esac
# (tested, but not put out)
[[ ${BUILD:-}/${RESULT:-} != success/@(ok|hold-agros|hold-upstream) || ${RELEASE:-} == success ]] ||
    state="the release didn't go through (${RELEASE:-not run}): nothing published"
open=$(gh issue list --label held --state open --json number -q '.[0].number')
if [[ $state == ok && -z $held ]]; then
    [[ -z $open ]] || gh issue close "$open" --comment "Everything built and passed again: $RUN_URL"
    echo "All out"
    exit 0
fi
[[ $state == ok ]] && state="built and tested, but some packages didn't build: the published ones kept"
body=$(mktemp)
{
    echo "**$state**"
    echo
    echo "Run: $RUN_URL"
    if [[ -n $held ]]; then
        echo
        echo "**Held back** (the published version kept, the rest went out):"
        sed 's/^/- /' <<<"$held"
    fi
    if [[ -n $report ]]; then
        echo
        echo "**Tests:**"
        echo "$report"
    fi
    echo
    echo "This issue is updated by each run, and closes itself once one puts everything out again."
} >"$body"
gh label create held --color D93F0B --description "CI held something back" --force >/dev/null 2>&1 || true
title="Held back: ${state%%:*}"
if [[ -n $open ]]; then
    gh issue edit "$open" --title "$title" --body-file "$body"
else
    gh issue create --label held --title "$title" --body-file "$body"
fi
rm -f "$body"
