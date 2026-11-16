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
sed "s|@T@|$t|g" >"$t/bin/gh" <<'GH'
#!/bin/bash
echo "gh $*" >>@T@/gh.log
q=. p=
for a; do [[ $p == -q ]] && q=$a; p=$a; done
json() { jq -r "$q" <<<"$1"; }
run() { echo "{\"status\": \"completed\", \"conclusion\": \"$1\", \"createdAt\": \"$2T03:00:00Z\", \"databaseId\": $3}"; }
case "$*" in
  "run list -R x/agros "*)
    if [[ $STATE == *ci-failed* ]]; then json "[$(run cancelled 2026-11-20 13), $(run failure 2026-11-19 12), $(run success 2026-11-18 11)]"
    elif [[ $STATE == *ci-quiet* ]]; then json "[$(run success 2026-11-14 12)]"
    elif [[ $STATE == *noruns* ]]; then json '[{"status": "in_progress", "conclusion": "", "createdAt": "2026-11-20T03:00:00Z", "databaseId": 14}]'
    else json "[$(run cancelled 2026-11-20 13), $(run success 2026-11-20 12)]"; fi ;;
  "run list -R x/iso -w iso.yml "*) json "[$(run success 2026-11-20 21)]" ;;
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
    [[ $STATE == *held* ]] && json '[{"title": "Held back: x", "url": "https://h", "createdAt": "2026-11-10T03:00:00Z"}]' || json '[]' ;;
  "pr list"*)
    [[ $STATE == *gh-down* ]] && exit 1
    [[ $STATE == *sync* ]] && json '[{"title": "CachyOS: 2 new commit(s)", "url": "https://p", "createdAt": "2026-11-12T03:00:00Z"}]' || json '[]' ;;
  "api repos/caelestia-dots/caelestia/compare/"*)
    [[ $STATE == *gh-down* ]] && exit 1
    json '{"ahead_by": 12, "base_commit": {"commit": {"committer": {"date": "2026-11-03T10:00:00Z"}}}}' ;;
  "issue list --label status --state all"*) cat @T@/lastbody 2>/dev/null; true ;;
  "issue list --label status"*) echo 7 ;;
  "issue create"*) for a; do [[ $p == --body-file ]] && cp "$a" @T@/body; p=$a; done ;;
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
        SIZES=${SIZES-$t/sizes} "$here/ci/status.sh" >/dev/null
}
last_sizes() { PATH=$t/bin:$PATH "$here/ci/status.sh" --last-sizes; }
go ""
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "all well not said: $(cat "$t/body")"
grep -qx 'gh issue close 7' "$t/gh.log" || fail "last week's status not closed"
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
for s in "AgrOS's CI: its last run failure (2026-11-19); last good 2026-11-18" "Held back: x (https://h, open since 2026-11-10)" \
    "CachyOS ISO changes waiting for a merge: CachyOS: 2 new commit(s) (https://p, open since 2026-11-12)" \
    "Hyprland 0.58.0 (Arch's) not approved yet: AgrOS's machines stay on 0.57.2"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
# (a lookup that fails is said, not read as nothing held, nothing waiting, nothing to approve)
go "gh-down pages-down arch-down"
for s in "CI's held issue couldn't be read: whether anything is held not checked" \
    "CachyOS ISO changes waiting for a merge: its pull request couldn't be read: not checked" \
    "AgrOS's approved list couldn't be read (https://crimzoagra.github.io/agros/x86_64/agros-approved): AgrOS's machines can't fetch it either" \
    "Arch's Hyprland version couldn't be read: whether it's approved not checked"; do
    grep -qxF -- "- $s" "$t/body" || fail "a failed lookup not said: $s: $(cat "$t/body")"
done
grep -qF "| Caelestia's dots | pinned ${dots:0:7}, upstream couldn't be read |" "$t/body" || fail "the dots' upstream not read said: $(cat "$t/body")"
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
