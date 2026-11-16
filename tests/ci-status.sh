#!/usr/bin/env bash
# ci/status.sh: the weekly issue says nothing broke when all is well, and lists what needs a look otherwise (a failed
# run, a held issue, CachyOS changes waiting, a Hyprland not approved); last week's closed, the owner mentioned. gh and
# curl are stand-ins, their answers as $STATE says (gh's run list: JSON through status.sh's own jq query, as gh -q
# runs it). A run list with nothing finished says "none", a baseline too big for the issue is left out, said
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
cat >"$t/bin/gh" <<'EOF'
#!/bin/bash
echo "gh $*" >>"$T/gh.log"
# run <status> <conclusion> <day>: one run's JSON
run() { printf '{"status": "%s", "conclusion": "%s", "createdAt": "%sT10:00:00Z"}' "$@"; }
case "$*" in
    "run list "*)
        for a; do [[ ${p:-} == -q ]] && q=$a; p=$a; done
        if [[ $STATE == *noruns* ]]; then
            echo "[$(run in_progress '' 2026-11-21)]"
        elif [[ $* == *x/agros* && $STATE == *ci-failed* ]]; then
            echo "[$(run completed failure 2026-11-19), $(run completed success 2026-11-18)]"
        else
            echo "[$(run in_progress '' 2026-11-21), $(run completed cancelled 2026-11-20), $(run completed success 2026-11-20)]"
        fi | jq -r "$q" ;;
    "issue list --label held"*) [[ $STATE == *held* ]] && echo "Held back: x (https://h)"; true ;;
    "pr list"*) [[ $STATE == *sync* ]] && echo "CachyOS: 2 new commit(s) (https://p)"; true ;;
    "issue list --label status --state all"*) cat "$T/lastbody" 2>/dev/null; true ;;
    "issue list --label status"*) echo 7 ;;
    "issue create"*) for a; do [[ ${p:-} == --body-file ]] && cp "$a" "$T/body"; p=$a; done ;;
esac
EOF
# shellcheck disable=SC2016
printf '#!/bin/bash\ncase "$*" in *agros-approved*) echo "hyprland 0.57.2" ;; *json*) [[ $STATE == *newhypr* ]] && echo "{\\"pkgver\\": \\"0.58.0\\"}" || echo "{\\"pkgver\\": \\"0.57.2\\"}" ;; esac\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
# (the size watch's out dir: what it found, its table rows, its baseline)
mkdir -p "$t/sizes"
echo '| The ISO: its packages | 3, 68 MiB installed |' >"$t/sizes/table"
printf '%s\n' 'iso hyprland 66560' 'inst cairo 1536' >"$t/sizes/baseline"
: >"$t/sizes/report"
go() { rm -f "$t/gh.log" "$t/body"; T=$t STATE=$1 PATH=$t/bin:$PATH GITHUB_REPOSITORY=x/agros OWNER=someone SIZES=${SIZES-$t/sizes} "$here/ci/status.sh" >/dev/null; }
last_sizes() { T=$t PATH=$t/bin:$PATH "$here/ci/status.sh" --last-sizes; }
go ""
grep -q '^@someone \*\*Nothing broke this week' "$t/body" || fail "all well not said: $(cat "$t/body")"
grep -qx 'gh issue close 7' "$t/gh.log" || fail "last week's status not closed"
grep -qxF '| The ISO: its packages | 3, 68 MiB installed |' "$t/body" || fail "the size watch's row not in the table: $(cat "$t/body")"
# (the last finished run, not the one going nor the cancelled one)
grep -qxF "| AgrOS's CI (packages) | last run success 2026-11-20, last good 2026-11-20 |" "$t/body" ||
    fail "the last run not read: $(cat "$t/body")"
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
for s in "AgrOS's CI: its last run failure (2026-11-19); last good 2026-11-18" "Held back: x (https://h)" \
    "CachyOS ISO changes waiting for a merge: CachyOS: 2 new commit(s) (https://p)" \
    "Hyprland 0.58.0 (Arch's) not approved yet: AgrOS's machines stay on 0.57.2"; do
    grep -qxF -- "- $s" "$t/body" || fail "not said: $s: $(cat "$t/body")"
done
# (a first week whose sets pacman couldn't work out: no baseline, but it ran, and what it found is said)
: >"$t/sizes/baseline"
echo "The ISO: pacman couldn't work out its packages, sizes not compared this week: error: x" >"$t/sizes/report"
go ""
grep -qxF -- "- The ISO: pacman couldn't work out its packages, sizes not compared this week: error: x" "$t/body" ||
    fail "the size watch's find without a baseline not said: $(cat "$t/body")"
grep -q "didn't run" "$t/body" && fail "a size watch that ran said not to have: $(cat "$t/body")"
: >"$t/sizes/report"
# (no run finished: none, not jq's null)
go noruns
grep -qxF -- "- AgrOS's CI: its last run none (-); last good none" "$t/body" || fail "no finished run: $(cat "$t/body")"
grep -q null "$t/body" && fail "null in the issue: $(cat "$t/body")"
# (a baseline too big for the issue: left out, said, the body within GitHub's 65536 characters)
od -An -tx1 -N 120000 /dev/urandom | tr -d ' 
' | fold -w 40 | sed 's/^/iso p/; s/$/ 1/' >"$t/sizes/baseline"
go ""
grep -q 'agros-sizes:' "$t/body" && fail "a baseline too big for the issue left in"
grep -qxF -- "- The size watch's baseline is too big for the issue: left out, so next week's sizes aren't compared" "$t/body" ||
    fail "a baseline too big not said: $(cat "$t/body")"
(($(wc -c <"$t/body") <= 65536)) || fail "the body is $(wc -c <"$t/body") bytes"
echo "ok ci-status"
