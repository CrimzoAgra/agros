#!/usr/bin/env bash
# CI's word on a run, as one GitHub issue (label "held"): opened, or brought up to date, when something was held back
# or nothing went out, or upstream's next release no longer fits AgrOS's changes (the report's AHEAD lines: nothing held,
# but a change to make before that release); closed, said why, once a run puts everything out with none of these. GitHub
# notifies of each (the repo's watchers: its owner), and the Friday status lists it while it's open. From the report
# job, gh with GH_TOKEN (issues: write). Environment:
#   RESULT   the tests' (ci/test-passes.sh): ok, hold-agros, hold-upstream, fail; empty: they didn't run
#   BUILD    the build job's result (success, failure...); RELEASE the release job's, the sign job's after it, or
#            Pages' deploy's after that
#   HELD     a file: what was held back, "<name>: <why>" each (build-repo.sh's AGROS_HELD)
#   REPORT   a file: the tests' report (test-passes.sh's AGROS_TEST_REPORT)
#   RUN_URL  this run's page
#   NEWER    true: the published repo was already a newer commit's (ci/newer.sh: this run a re-run of an older one),
#            nothing put out. Nothing said: the issue stays as the newer commit's run left it
set -uo pipefail
shopt -s extglob
[[ ${NEWER:-} != true ]] || { echo "A newer commit's repo is already published: this run put nothing out, nothing said"; exit 0; }
held=$(cat "${HELD:-/dev/null}" 2>/dev/null)
report=$(cat "${REPORT:-/dev/null}" 2>/dev/null)
ahead=$(grep '^    AHEAD ' <<<"$report")
# (GitHub refuses an issue's text over 65536 characters, every try, and the issue then went on saying an earlier run's:
# the tests' report that long, every test failing in all three passes with its why, cut short, said, its first lines
# kept. The whole of it is the run's report artifact)
if ((${#report} > ${AGROS_REPORT_MAX:-50000})); then
    report=$(awk -v max="${AGROS_REPORT_MAX:-50000}" '{ n += length($0) + 1 } n <= max { print; next } { cut++ }
        END { print "    ... cut short here, " cut " more lines: the run\047s report artifact has them all" }' <<<"$report")
fi
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
# again <command>...: tried up to three times (GitHub's API drops a call now and then). One that still fails fails the
# report job, so the run shows it and the Friday status says CI's last run failed; the next run tries again. (Never
# read as no issue open: that opened a second one beside it, or left one open with the run saying all went out)
again() {
    local i
    for i in 1 2 3; do
        "$@" && return 0
        ((i == 3)) || sleep "${AGROS_RETRY_WAIT:-20}"
    done
    echo "::error::gh ${2:-} ${3:-} failed three times: CI's held issue not brought up to date" >&2
    return 1
}
# (every open one: a second one, from a create GitHub made but answered as failed, closed beside the first)
open=$(again gh issue list --label held --state open --json number -q '.[].number') || exit 1
read -r first others <<<"$(paste -sd' ' <<<"$open")"
if [[ $state == ok && -z $held && -z $ahead ]]; then
    for n in $open; do
        again gh issue close "$n" --comment "Everything built and passed again: $RUN_URL" || exit 1
    done
    echo "All out"
    exit 0
fi
title="Held back"
if [[ $state == ok && -n $held ]]; then
    state="built and tested, but some packages didn't build: the published ones kept"
elif [[ $state == ok ]]; then
    state="upstream's next release no longer fits AgrOS's changes: everything went out, nothing held" title=Heads-up
fi
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
    echo "This issue is updated by each run, and closes itself once one puts everything out again, with nothing of upstream's next release to adapt."
} >"$body"
gh label create held --color D93F0B --description "CI held something back" --force >/dev/null 2>&1 || true
title="$title: ${state%%:*}"
rc=0
if [[ -n $first ]]; then
    again gh issue edit "$first" --title "$title" --body-file "$body" || rc=1
    for n in $others; do again gh issue close "$n" --comment "A second copy of #$first: said there" || rc=1; done
else
    again gh issue create --label held --title "$title" --body-file "$body" || rc=1
fi
rm -f "$body"
exit "$rc"
