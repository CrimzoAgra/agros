#!/usr/bin/env bash
# ci/status.sh: the weekly issue says nothing broke when all is well, and lists what needs a look otherwise (a failed
# run, a held issue, CachyOS changes waiting, a Hyprland not approved, and each of these that couldn't be looked up);
# last week's closed, the owner mentioned. gh and curl are stand-ins, their answers as $STATE says
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# (gh's answers as JSON, its -q run on them by jq, as the real one does: the queries are checked too)
# shellcheck disable=SC2016
cpin=$(sed -n 's/^ *calamares_pkgbuild=//p' "$here/ci/build-repo.sh")
csrc=$(sed -n 's/^ *calamares_src=//p' "$here/ci/build-repo.sh")
sed -e "s|@T@|$t|g" -e "s|@PIN@|$cpin|g" -e "s|@SRC@|$csrc|g" >"$t/bin/gh" <<'GH'
#!/bin/bash
echo "gh $*" >>@T@/gh.log
q=. p=
for a; do [[ $p == -q ]] && q=$a; p=$a; done
json() { jq -r "$q" <<<"$1"; }
run() { echo "{\"status\": \"completed\", \"conclusion\": \"$1\", \"createdAt\": \"$2T03:00:00Z\", \"databaseId\": $3, \"event\": \"${4:-push}\"}"; }
case "$*" in
  # (the mirror: skipped after a pull request's CI run, which says nothing; or failed)
  "run list -R x/agros -w mirror.yml "*)
    if [[ $STATE == *mirror-failed* ]]; then json "[$(run skipped 2026-11-20 43), $(run failure 2026-11-19 41), $(run success 2026-11-18 40)]"
    else json "[$(run skipped 2026-11-20 42), $(run success 2026-11-20 41)]"; fi ;;
  "api repos/x/agros/actions/runs/41/jobs "*) json '{"jobs": [{"name": "mirror", "conclusion": "failure"}]}' ;;
  # (the keepalives: agros's not run yet, agros-iso's run, or failed)
  "run list -R x/agros -w keepalive.yml "*) json '[]' ;;
  "run list -R x/iso -w keepalive.yml "*)
    if [[ $STATE == *keep-failed* ]]; then json "[$(run failure 2026-11-09 51), $(run success 2026-10-09 50)]"
    else json "[$(run success 2026-11-09 50)]"; fi ;;
  "api repos/x/iso/actions/runs/51/jobs "*) json '{"jobs": [{"name": "keepalive", "conclusion": "failure"}]}' ;;
  "run list -R x/agros -w ci.yml "*)
    if [[ $STATE == *ci-failed* || $STATE == *ci-isojob* ]]; then json "[$(run cancelled 2026-11-20 13), $(run failure 2026-11-19 12), $(run success 2026-11-18 11)]"
    # (a pull request from a fork's own main branch, listed as main's: its tests on the published repo passed)
    elif [[ $STATE == *ci-pr* ]]; then json "[$(run success 2026-11-20 13 pull_request), $(run failure 2026-11-19 12), $(run success 2026-11-18 11)]"
    elif [[ $STATE == *ci-quiet* ]]; then json "[$(run success 2026-11-14 12)]"
    elif [[ $STATE == *noruns* ]]; then json '[{"status": "in_progress", "conclusion": "", "createdAt": "2026-11-20T03:00:00Z", "databaseId": 14}]'
    else json "[$(run cancelled 2026-11-20 13), $(run success 2026-11-20 12)]"; fi ;;
  "run list -R x/iso -w iso.yml "*)
    if [[ $STATE == *iso-failed* ]]; then json "[$(run failure 2026-11-20 22), $(run success 2026-11-18 21)]"
    else json "[$(run success 2026-11-20 21)]"; fi ;;
  # (a failed run's jobs: CI's tests, or only its iso job (the ISO's start); the ISO's SourceForge key)
  "api repos/x/agros/actions/runs/12/jobs "*)
    [[ $STATE == *gh-down* ]] && exit 1
    t=failure i=skipped; [[ $STATE != *ci-isojob* ]] || t=success i=failure
    json "{\"jobs\": [{\"name\": \"test\", \"conclusion\": \"$t\"}, {\"name\": \"report\", \"conclusion\": \"success\"}, {\"name\": \"iso\", \"conclusion\": \"$i\"}]}" ;;
  "api repos/x/iso/actions/runs/22/jobs "*)
    json '{"jobs": [{"name": "sourceforge", "conclusion": "failure"}, {"name": "iso", "conclusion": "skipped"}]}' ;;
  "run list -R x/iso -w cachyos-sync.yml "*)
    if [[ $STATE == *cachy-broken* || $STATE == *cachy-checkfail* ]]; then json "[$(run failure 2026-11-20 31), $(run success 2026-11-18 30)]"
    elif [[ $STATE == *cachy-quiet* ]]; then json "[$(run success 2026-11-01 31)]"
    else json "[$(run success 2026-11-20 31)]"; fi ;;
  # (the ISO's jobs: held by the upstream gate, its Upstream gate step run and its publish skipped; already published,
  # neither run; else published)
  "api repos/x/iso/actions/runs/21/jobs "*)
    gate=success publish=success
    [[ $STATE != *iso-gate* ]] || publish=skipped
    [[ $STATE != *iso-cached* ]] || gate=skipped publish=skipped
    json "{\"jobs\": [{\"name\": \"iso\", \"conclusion\": \"success\", \"steps\": [{\"name\": \"Upstream gate\", \"conclusion\": \"$gate\"}]},
      {\"name\": \"publish\", \"conclusion\": \"$publish\", \"steps\": []}]}" ;;
  # (the sync's jobs: its own step failing, or only its ISO check, whose pull request says so)
  "api repos/x/iso/actions/runs/31/jobs "*)
    prepare=success check=skipped merge=skipped
    [[ $STATE != *cachy-broken* ]] || prepare=failure
    [[ $STATE != *cachy-checkfail* ]] || check=failure merge=success
    json "{\"jobs\": [{\"name\": \"prepare\", \"conclusion\": \"$prepare\"}, {\"name\": \"check / iso\", \"conclusion\": \"$check\"},
      {\"name\": \"merge\", \"conclusion\": \"$merge\"}]}" ;;
  "issue list --label held"*)
    [[ $STATE == *gh-down* ]] && exit 1
    if [[ $STATE == *held2* ]]; then json '[{"title": "Held back: x", "url": "https://h", "createdAt": "2026-11-10T03:00:00Z"},
      {"title": "Heads-up: y", "url": "https://h2", "createdAt": "2026-11-11T03:00:00Z"}]'
    elif [[ $STATE == *held* ]]; then json '[{"title": "Held back: x", "url": "https://h", "createdAt": "2026-11-10T03:00:00Z"}]'
    else json '[]'; fi ;;
  "pr list"*)
    [[ $STATE == *gh-down* ]] && exit 1
    [[ $STATE == *sync* ]] && json '[{"title": "CachyOS: 2 new commit(s)", "url": "https://p", "createdAt": "2026-11-12T03:00:00Z"}]' || json '[]' ;;
  "api repos/caelestia-dots/caelestia/compare/"*)
    [[ $STATE == *gh-down* ]] && exit 1
    json '{"ahead_by": 12, "base_commit": {"commit": {"committer": {"date": "2026-11-03T10:00:00Z"}}}}' ;;
  # (CachyOS's installer recipe: the newest commit on it, AgrOS's pin unless it has moved on)
  "api repos/CachyOS/CachyOS-PKGBUILDS/commits?path=cachyos-calamares"*)
    [[ $STATE == *gh-down* ]] && exit 1
    sha=@PIN@; [[ $STATE == *calamares-moved* ]] && sha=9999abcdaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    json "[{\"sha\": \"$sha\", \"commit\": {\"committer\": {\"date\": \"2026-11-17T08:10:48Z\"}}}]" ;;
  # (...and its code: new commits on the cachyos branch since AgrOS's pinned one, none unless it has moved on)
  "api repos/CachyOS/cachyos-calamares/compare/@SRC@...cachyos "*)
    [[ $STATE == *gh-down* ]] && exit 1
    n=0; [[ $STATE == *calamares-src-moved* ]] && n=6
    json "{\"ahead_by\": $n, \"base_commit\": {\"commit\": {\"committer\": {\"date\": \"2026-11-16T20:00:00Z\"}}}}" ;;
  # (the last status made: last Friday's, or the one before when last week's never went out)
  "issue list --label status --state all -L 1 --json createdAt "*)
    [[ $STATE == *gh-down* ]] && exit 1
    [[ $STATE == *status-missed* ]] && json '[{"createdAt": "2026-11-06T17:02:00Z"}]' || json '[{"createdAt": "2026-11-13T17:02:00Z"}]' ;;
  "issue list --label status --state all"*) cat @T@/lastbody 2>/dev/null; true ;;
  # (last week's, 7, the one just made, 8, and 9, another run's made at the same time; making it fails while
  # @T@/createfail is there)
  "issue list --label status"*) echo 7; echo 8; echo 9 ;;
  "issue create"*)
    [[ -e @T@/createfail ]] && exit 1
    for a; do [[ $p == --body-file ]] && cp "$a" @T@/body; p=$a; done
    echo https://github.com/x/agros/issues/8 ;;
esac
GH
# shellcheck disable=SC2016
printf '#!/bin/bash\ncase "$*" in *agros-approved*) [[ $STATE == *pages-down* ]] && exit 22; echo "hyprland 0.57.2" ;; *json*) [[ $STATE == *arch-down* ]] && exit 22; [[ $STATE == *newhypr* ]] && echo "{\\"pkgver\\": \\"0.58.0\\"}" || echo "{\\"pkgver\\": \\"0.57.2\\"}" ;; esac\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
# (the size watch's out dir: what it found, its table rows, its baseline)
mkdir -p "$t/sizes"
echo '| The ISO: its packages | 3, 68 MiB installed |' >"$t/sizes/table"
printf '%s\n' 'iso hyprland 66560' 'inst cairo 1536' >"$t/sizes/baseline"
: >"$t/sizes/report"
go() {
    rm -f "$t/gh.log" "$t/body"
    STATE=$1 PATH=$t/bin:$PATH GITHUB_REPOSITORY=x/agros AGROS_ISO_REPO=x/iso AGROS_NOW=2026-11-20 OWNER=someone \
        SIZES=${SIZES-$t/sizes} AGROS_RETRY_WAIT=0 "$here/ci/status.sh" >/dev/null
}
last_sizes() { PATH=$t/bin:$PATH "$here/ci/status.sh" --last-sizes; }
go ""
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "all well not said: $(cat "$t/body")"
grep -qx 'gh issue close 7' "$t/gh.log" || fail "last week's status not closed"
grep -q 'gh issue close [89]' "$t/gh.log" && fail "this week's status (or another run's, newer) closed: $(cat "$t/gh.log")"
[[ $(grep -n '^gh issue \(create\|close\)' "$t/gh.log" | head -1) == *create* ]] ||
    fail "last week's status closed before this week's was made: $(cat "$t/gh.log")"
# (GitHub's API failing to make it: tried three times, then the run fails, last week's left open; never a run that
# passes with no status sent)
touch "$t/createfail"
rc=0; go "" 2>/dev/null || rc=$?
((rc)) || fail "no status made, and the run passed"
[[ $(grep -c '^gh issue create' "$t/gh.log") == 3 ]] || fail "making the status not tried three times: $(cat "$t/gh.log")"
grep -q '^gh issue close' "$t/gh.log" && fail "last week's status closed with no new one: $(cat "$t/gh.log")"
rm "$t/createfail"
go ""
grep -qxF '| The ISO: its packages | 3, 68 MiB installed |' "$t/body" || fail "the size watch's row not in the table: $(cat "$t/body")"
# (how far Caelestia's dots have gone since the pinned commit: in the table, not a problem)
dots=$(sed -n 's/^_dots=//p' "$here/packages/agros-hyprland-settings/PKGBUILD")
grep -qxF "| Caelestia's dots | pinned ${dots:0:7} (2026-11-03), 12 newer commit(s) upstream |" "$t/body" ||
    fail "the dots' pin not in the table: $(cat "$t/body")"
grep -qF "compare/$dots...HEAD" "$t/gh.log" || fail "not compared from the pinned commit: $(cat "$t/gh.log")"
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
SIZES='' GITHUB_RUN_ID=42 go ""
grep -qxF -- "- The size watch didn't run (status.yml's Sizes step, its log: https://github.com/x/agros/actions/runs/42): sizes not compared this week" "$t/body" ||
    fail "the size watch not running not said: $(cat "$t/body")"
cp "$t/body" "$t/lastbody"
[[ $(last_sizes) == $'iso hyprland 66560\ninst cairo 1536' ]] || fail "last week's baseline not kept: $(last_sizes)"
go "ci-failed held sync newhypr"
grep -q '^@someone \*\*Needs a look' "$t/body" || fail "problems not said: $(cat "$t/body")"
for s in "AgrOS's CI: its last run failure (2026-11-19; test failed, https://github.com/x/agros/actions/runs/12); last good 2026-11-18" "Held back: x (https://h, open since 2026-11-10)" \
    "CachyOS ISO changes waiting for a merge: CachyOS: 2 new commit(s) (https://p, open since 2026-11-12)" \
    "Hyprland 0.58.0 (Arch's) not approved yet: AgrOS's machines stay on 0.57.2"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
# (two held issues open: each its own item)
go "held2"
for s in "Held back: x (https://h, open since 2026-11-10)" "Heads-up: y (https://h2, open since 2026-11-11)"; do
    grep -qxF -- "- $s" "$t/body" || fail "an open held issue not its own item: $s: $(cat "$t/body")"
done
# (a pull request's run isn't main's: main's failure still said)
go "ci-pr"
grep -qxF -- "- AgrOS's CI: its last run failure (2026-11-19; test failed, https://github.com/x/agros/actions/runs/12); last good 2026-11-18" "$t/body" ||
    fail "a pull request's run taken for main's: $(cat "$t/body")"
# (a failed run says which of its jobs failed, with its page: CI's iso job alone, the ISO build not started; the ISO's
# own, its SourceForge key; its jobs not read, said)
go "ci-isojob iso-failed"
for s in "AgrOS's CI: its last run failure (2026-11-19; iso failed, https://github.com/x/agros/actions/runs/12: the packages went out, but agros-iso's ISO build wasn't started (the AGROS_ISO_TOKEN secret expired or lost its access? Its log says)); last good 2026-11-18" \
    "The ISO: its last build failure (2026-11-20; sourceforge failed, https://github.com/x/iso/actions/runs/22); last good 2026-11-18"; do
    grep -qxF -- "- $s" "$t/body" || fail "a failed run's jobs not said: $s: $(cat "$t/body")"
done
go "ci-failed gh-down"
grep -qF -- "- AgrOS's CI: its last run failure (2026-11-19; its jobs couldn't be read, https://github.com/x/agros/actions/runs/12)" "$t/body" ||
    fail "a failed run's jobs not read not said: $(cat "$t/body")"
# (the R2 mirror and each keepalive: a failed last run said, a skipped one passed over, none run yet nothing to say)
go ""
grep -qxF "| The R2 mirror | last run success 2026-11-20, last good 2026-11-20 |" "$t/body" || fail "the mirror's row: $(cat "$t/body")"
go "mirror-failed keep-failed"
for s in "The R2 mirror: its last run failure (2026-11-19; mirror failed, https://github.com/x/agros/actions/runs/41); last good 2026-11-18: machines that fall back to it (Pages down) get older packages" \
    "The keepalive of iso: its last run failure (2026-11-09; keepalive failed, https://github.com/x/iso/actions/runs/51): GitHub turns its scheduled workflows off after 60 days without a commit"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
grep -qxF "| Keepalive | last run agros none -, iso failure 2026-11-09 |" "$t/body" || fail "the keepalives' row: $(cat "$t/body")"
# (a lookup that fails is said, not read as nothing held, nothing waiting, nothing to approve)
go "gh-down pages-down arch-down"
for s in "CI's held issue couldn't be read: whether anything is held not checked" \
    "CachyOS ISO changes waiting for a merge: its pull request couldn't be read: not checked" \
    "AgrOS's approved list couldn't be read (https://crimzoagra.github.io/agros/x86_64/agros-approved): AgrOS's machines can't fetch it either" \
    "Arch's Hyprland version couldn't be read: whether it's approved not checked"; do
    grep -qxF -- "- $s" "$t/body" || fail "a failed lookup not said: $s: $(cat "$t/body")"
done
grep -qF "| Caelestia's dots | pinned ${dots:0:7}, upstream couldn't be read |" "$t/body" || fail "the dots' upstream not read said: $(cat "$t/body")"
grep -qxF -- "- CachyOS's installer recipe couldn't be read: whether it changed since AgrOS's pin not checked" "$t/body" ||
    fail "CachyOS's installer recipe not read not said: $(cat "$t/body")"
grep -qxF -- "- CachyOS's installer code couldn't be read: whether it changed since AgrOS's pin not checked" "$t/body" ||
    fail "CachyOS's installer code not read not said: $(cat "$t/body")"
grep -qxF -- "- Last week's status couldn't be looked up: whether it went out not checked" "$t/body" ||
    fail "last week's status not looked up not said: $(cat "$t/body")"
# (a Friday with no status: its run failed, or GitHub dropped it; last week's there, nothing said)
go "status-missed"
grep -qxF -- "- No status went out last week (the last one: 2026-11-06): status.yml's run failed or never started, https://github.com/x/agros/actions/workflows/status.yml" "$t/body" ||
    fail "a week with no status not said: $(cat "$t/body")"
# (CachyOS's installer recipe, or its code, moved on past AgrOS's pins: a look needed; neither said when they haven't)
go "calamares-moved calamares-src-moved"
grep -qxF -- "- CachyOS changed its installer's recipe (cachyos-calamares, 9999abcd, 2026-11-17) since AgrOS's pin (${cpin:0:8}): look at it, then move calamares_pkgbuild on (ci/build-repo.sh)" "$t/body" ||
    fail "CachyOS's installer recipe moving on not said: $(cat "$t/body")"
grep -qxF -- "- CachyOS's installer has 6 new commit(s) on its cachyos branch since AgrOS's pin (${csrc:0:8}, 2026-11-16): look at them, then move calamares_src on (ci/build-repo.sh)" "$t/body" ||
    fail "CachyOS's installer code moving on not said: $(cat "$t/body")"
go ""
grep -q "CachyOS's installer\|CachyOS changed its installer" "$t/body" && fail "CachyOS's installer said to have moved when it hasn't: $(cat "$t/body")"
go "arch-down"
grep -q "approved list" "$t/body" && fail "a readable approved list said unreadable: $(cat "$t/body")"
# (the ISO held by the upstream gate: GitHub's success, said; one already published isn't)
go "iso-gate"
grep -qxF -- "- The ISO: its last build (2026-11-20) waits for AgrOS's check of its Hyprland or a library: nothing built, the ISO published before stays the download" "$t/body" ||
    fail "the ISO held by the upstream gate not said: $(cat "$t/body")"
grep -qF '| The ISO | last build waiting 2026-11-20' "$t/body" || fail "the ISO's row doesn't say it waits: $(cat "$t/body")"
go "iso-cached"
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "an ISO already published said to need a look: $(cat "$t/body")"
# (the CachyOS sync failing itself: said; only its ISO check failing is its pull request's to say)
go "cachy-broken"
grep -qxF -- "- The CachyOS sync: its last run failure (2026-11-20; prepare); last good 2026-11-18: CachyOS's changes not followed" "$t/body" ||
    fail "the CachyOS sync failing not said: $(cat "$t/body")"
go "cachy-checkfail"
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "the sync's ISO check said apart from its pull request: $(cat "$t/body")"
# (a daily run not seen for days: GitHub turned its schedule off)
go "ci-quiet cachy-quiet"
for s in "AgrOS's CI hasn't run since 2026-11-14: its daily run turned off?" \
    "The CachyOS sync hasn't run since 2026-11-01: its daily run turned off?"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
# (no run finished: none, not jq's null)
go noruns
grep -qxF -- "- AgrOS's CI: its last run none (-); last good none" "$t/body" || fail "no finished run: $(cat "$t/body")"
grep -q null "$t/body" && fail "null in the issue: $(cat "$t/body")"
# (a first week whose sets pacman couldn't work out: no baseline, but it ran, and what it found is said)
: >"$t/sizes/baseline"
echo "The ISO: pacman couldn't work out its packages, sizes not compared this week: error: x" >"$t/sizes/report"
go ""
grep -qxF -- "- The ISO: pacman couldn't work out its packages, sizes not compared this week: error: x" "$t/body" ||
    fail "the size watch's find without a baseline not said: $(cat "$t/body")"
grep -q "didn't run" "$t/body" && fail "a size watch that ran said not to have: $(cat "$t/body")"
: >"$t/sizes/report"
# (a baseline too big for the issue: left out, said, the body within GitHub's 65536 characters)
od -An -tx1 -N 120000 /dev/urandom | tr -d ' \n' | fold -w 40 | sed 's/^/iso p/; s/$/ 1/' >"$t/sizes/baseline"
go ""
grep -q 'agros-sizes:' "$t/body" && fail "a baseline too big for the issue left in"
grep -qxF -- "- The size watch's baseline is too big for the issue: left out, so next week's sizes aren't compared" "$t/body" ||
    fail "a baseline too big not said: $(cat "$t/body")"
(($(wc -c <"$t/body") <= 65536)) || fail "the body is $(wc -c <"$t/body") bytes"
echo "ok ci-status"
