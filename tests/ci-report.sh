#!/usr/bin/env bash
# ci/report.sh: one issue for what CI held back; opened, then edited, never a second one; closed once a run puts
# everything out again; nothing done when all went out and none was open. gh is a stand-in
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# (GitHub's API down: $t/listfail fails the list, $t/writefail the rest)
sed "s|@T@|$t|g" >"$t/bin/gh" <<'GH'
#!/bin/bash
echo "gh $*" >>@T@/gh.log
case "$1 $2" in
  "issue list") [[ -e @T@/listfail ]] && exit 1; cat @T@/open 2>/dev/null; true ;;
  "issue view") [[ -e @T@/listfail ]] && exit 1; cat @T@/title 2>/dev/null; true ;;
  "issue create"|"issue edit"|"issue close"|"issue comment")
    [[ -e @T@/writefail || ( -e @T@/commentfail && $2 == comment ) ]] && exit 1
    b=; for a; do [[ $p == --body-file ]] && { cp "$a" @T@/body; b=$a; }; p=$a; done
    # (as GitHub: a body over 65536 characters refused)
    [[ -z $b || $(wc -m <"$b") -le 65536 ]] ;;
esac
GH
chmod +x "$t/bin/gh"
# (the held list and the tests' report empty files unless a case gives its own, as the report job downloads them)
: >"$t/none"
go() { rm -f "$t/gh.log"; PATH=$t/bin:$PATH RUN_URL=https://run AGROS_RETRY_WAIT=0 HELD=$t/none REPORT=$t/none "$@" "$here/ci/report.sh" >/dev/null; grep -v '^gh issue list\|^gh issue view\|^gh label' "$t/gh.log" || true; }
said() { local rc=0; rm -f "$t/gh.log"; PATH=$t/bin:$PATH RUN_URL=https://run AGROS_RETRY_WAIT=0 HELD=$t/none REPORT=$t/none "$@" "$here/ci/report.sh" >/dev/null 2>&1 || rc=$?; return "$rc"; }
echo "quickshell-git: AgrOS's fix didn't build" >"$t/held"
[[ $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held") == "gh issue create --label held --title Held back: built and tested, but some packages were held back (below) --body-file "* ]] ||
    fail "a held package didn't open an issue: $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held")"
grep -q '^- quickshell-git: ' "$t/body" || fail "the issue doesn't say what was held: $(cat "$t/body")"
echo 12 >"$t/open"
printf -- '- With this run'"'"'s [agros]:\n    FAIL lutris: x\n' >"$t/report"
[[ $(go env BUILD=success RELEASE=success RESULT=hold-upstream REPORT="$t/report") == "gh issue edit 12 --title Held back: an Arch update broke AgrOS's tests --body-file "* ]] ||
    fail "the open issue not brought up to date: $(go env BUILD=success RELEASE=success RESULT=hold-upstream REPORT="$t/report")"
grep -q 'FAIL lutris' "$t/body" || fail "the issue doesn't say which tests failed"
[[ $(go env BUILD=success RELEASE=failure RESULT=ok) == "gh issue edit 12 --title Held back: the release didn't go through (failure) --body-file "* ]] ||
    fail "a failed release not said: $(go env BUILD=success RELEASE=failure RESULT=ok)"
[[ $(go env BUILD=success RESULT=) == "gh issue edit 12 --title Held back: the tests didn't run to the end (a step before them failed) --body-file "* ]] ||
    fail "tests that didn't run not said: $(go env BUILD=success RESULT=)"
[[ $(go env BUILD=failure) == "gh issue edit 12 --title Held back: the repo didn't build (failure) --body-file "* ]] ||
    fail "a failed build not said: $(go env BUILD=failure)"
[[ $(go env BUILD=success RELEASE=success RESULT=ok) == "gh issue close 12 --comment Everything built and passed again: https://run" ]] ||
    fail "the issue not closed once all went out: $(go env BUILD=success RELEASE=success RESULT=ok)"
rm "$t/open"
[[ -z $(go env BUILD=success RELEASE=success RESULT=ok) ]] || fail "an issue touched with all out and none open"
# A release that went through, its held list or the tests' report not downloaded: the report job fails, the issue as
# it was (read as nothing held, it closed the issue as all out)
echo 12 >"$t/open"
for miss in "HELD=$t/gone" "REPORT=$t/gone"; do
    # shellcheck disable=SC2086  # (the variable, a word)
    ! said env BUILD=success RELEASE=success RESULT=ok $miss || fail "$miss with the release through: the report job passed"
    ! grep -qs '^gh issue \(close\|edit\|create\)' "$t/gh.log" || fail "$miss: the issue touched: $(cat "$t/gh.log")"
done
# (the release not through: none made, read as none)
[[ $(go env BUILD=success RELEASE=failure RESULT=ok HELD="$t/gone" REPORT="$t/gone") == "gh issue edit 12 "* ]] ||
    fail "a failed release without the artifacts not said"
rm "$t/open"
# A report too long for an issue (every test failing in all three passes, each with its why): cut short, said, its
# first lines and the state kept, rather than GitHub refusing the issue every time
rm -f "$t/body"
{ echo "- With this run's [agros], on today's Arch:"; for i in $(seq 1500); do printf '    FAIL test%s: %0100d\n' "$i" 0; done; } >"$t/long"
[[ $(go env BUILD=success RESULT=fail REPORT="$t/long") == "gh issue create --label held --title Held back: AgrOS's own code fails its tests --body-file "* ]] ||
    fail "a long report not said: $(go env BUILD=success RESULT=fail REPORT="$t/long")"
(($(wc -m <"$t/body") <= 65536)) || fail "a long report's issue over GitHub's 65536 characters: $(wc -m <"$t/body")"
grep -q '^    FAIL test1: ' "$t/body" && grep -q "^    \.\.\. cut short here, [0-9]* more lines: the run's report artifact" "$t/body" ||
    fail "a long report not cut short, said: $(head -c 300 "$t/body")"
# (a pass of the tests that couldn't run, ci/test-passes.sh's "!!" line: not said as AgrOS's own code failing)
printf -- '- With this run'"'"'s [agros], on today'"'"'s Arch:\n    FAIL lutris: x\n    !! the published [agros] didn'"'"'t install: not known which side broke the tests\n' >"$t/stopped"
[[ $(go env BUILD=success RESULT=fail REPORT="$t/stopped") == "gh issue create --label held --title Held back: the tests couldn't be run through (said below) --body-file "* ]] ||
    fail "tests that couldn't run through said as AgrOS's code failing: $(go env BUILD=success RESULT=fail REPORT="$t/stopped")"
# A re-run of an older run, the published repo already a newer commit's (ci/newer.sh): nothing put out, the issue as
# the newer run left it, neither opened nor closed nor edited
echo 12 >"$t/open"
for r in "RELEASE=skipped RESULT=hold-agros HELD=$t/held" "RELEASE=skipped RESULT=ok"; do
    rm -f "$t/gh.log"
    # shellcheck disable=SC2086  # (the variables, each a word)
    PATH=$t/bin:$PATH RUN_URL=https://run AGROS_RETRY_WAIT=0 env BUILD=success NEWER=true $r "$here/ci/report.sh" >/dev/null ||
        fail "a re-run of an older run failed the report ($r)"
    [[ ! -e $t/gh.log ]] || fail "an issue touched by a re-run of an older run ($r): $(cat "$t/gh.log")"
done
rm "$t/open"
# Upstream's next release no longer fitting (the report's AHEAD lines): all went out, but the issue opened, said as a
# heads-up, kept open while it lasts, closed once it's gone
printf -- '- With this run'"'"'s [agros], on today'"'"'s Arch:\n    all passed\n- Upstream'"'"'s next release...:\n    AHEAD lutris-overlay: x\n' >"$t/report"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue create --label held --title Heads-up: upstream's next release no longer fits AgrOS's changes --body-file "* ]] ||
    fail "upstream's next release not fitting didn't open an issue: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
grep -q 'AHEAD lutris-overlay: x' "$t/body" || fail "the issue doesn't say what doesn't fit: $(cat "$t/body")"
echo 13 >"$t/open"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue edit 13 --title Heads-up: "* ]] ||
    fail "the heads-up closed while it lasts: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
[[ $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" REPORT="$t/report") == "gh issue edit 13 --title Held back: built and tested, but some packages were held back (below) --body-file "* ]] ||
    fail "a hold not said over the heads-up: $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" REPORT="$t/report")"
sed -i '/AHEAD/d' "$t/report"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue close 13 "* ]] ||
    fail "the heads-up not closed once it's gone: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
# What a new install fails with that holding couldn't help (or the install test not run: ci/install-test.sh): all went
# out, the issue opened, said, kept open while it lasts; a hold over it said as one
rm -f "$t/open"
[[ $(go env BUILD=success RELEASE=success RESULT=ok INSTALL="agros-system: a new install fails with it, as published too") == "gh issue create --label held --title Heads-up: a new install of the release didn't go through (below), and holding a package couldn't help --body-file "* ]] ||
    fail "a new install failing didn't open an issue: $(go env BUILD=success RELEASE=success RESULT=ok INSTALL=x)"
grep -q '^- agros-system: a new install fails with it, as published too$' "$t/body" || fail "the issue doesn't say what a new install fails with: $(cat "$t/body")"
echo 13 >"$t/open"
[[ $(go env BUILD=success RELEASE=success RESULT=ok INSTALL=x HELD="$t/held") == "gh issue edit 13 --title Held back: "* ]] ||
    fail "a hold not said over a new install failing: $(go env BUILD=success RELEASE=success RESULT=ok INSTALL=x HELD="$t/held")"
[[ $(go env BUILD=success RELEASE=success RESULT=ok) == "gh issue close 13 "* ]] || fail "the issue not closed once a new install goes through"
rm "$t/open"
# (the tests' hold: the new build that broke them named in the held list)
echo "caelestia-shell: its new build fails AgrOS's tests lutris (they pass with the published one)" >"$t/held2"
[[ $(go env BUILD=success RELEASE=success RESULT=hold-agros HELD="$t/held2") == "gh issue create --label held --title Held back: a new AUR build broke AgrOS's tests --body-file "* ]] &&
    grep -q "^- caelestia-shell: its new build fails AgrOS's tests lutris" "$t/body" ||
    fail "the new build that broke the tests not said: $(go env BUILD=success RELEASE=success RESULT=hold-agros HELD="$t/held2") $(cat "$t/body")"
# GitHub's API failing: never read as no issue open (a second one opened beside it, or one left open with the run
# saying all went out), and the report job fails (the run shows it, the Friday status says it) rather than passing
echo 12 >"$t/open"
touch "$t/listfail"
! said env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" || fail "the open issue couldn't be looked up, and the report job passed"
grep -q '^gh issue \(create\|edit\)' "$t/gh.log" && fail "an issue written while the open one couldn't be looked up: $(cat "$t/gh.log")"
[[ $(grep -c '^gh issue list' "$t/gh.log") == 3 ]] || fail "the lookup not tried three times: $(cat "$t/gh.log")"
! said env BUILD=success RELEASE=success RESULT=ok || fail "all out said with the open issue not looked up (left open)"
rm "$t/listfail"
touch "$t/writefail"
! said env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" || fail "the issue couldn't be brought up to date, and the report job passed"
! said env BUILD=success RELEASE=success RESULT=ok || fail "the issue couldn't be closed, and the report job passed"
rm "$t/writefail"
# (two open, a create GitHub made but answered as failed: the first brought up to date, the second closed; both
# closed once all is out)
printf '%s\n' 12 14 >"$t/open"
out=$(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held")
[[ $out == "gh issue edit 12 "*$'\n'"gh issue close 14 --comment A second copy of #12: said there" ]] ||
    fail "a second open issue not closed: $out"
out=$(go env BUILD=success RELEASE=success RESULT=ok)
[[ $out == "gh issue close 12 "*$'\n'"gh issue close 14 "* ]] || fail "not every open issue closed once all went out: $out"
# The open one brought up to date with a new state: said in a comment too (an edit notifies no one: a Heads-up turned
# into nothing published went unseen until Friday's status); the same state again, or its title not read: as said
rm -f "$t/title"; echo 12 >"$t/open"
echo "Heads-up: upstream's next release no longer fits AgrOS's changes" >"$t/title"
out=$(go env BUILD=success RESULT=fail REPORT="$t/report")
[[ $out == "gh issue edit 12 --title Held back: AgrOS's own code fails its tests --body-file "*$'\n'"gh issue comment 12 --body Now **AgrOS's own code fails its tests: nothing published**: https://run" ]] ||
    fail "a new state of the open issue not said in a comment: $out"
echo "Held back: AgrOS's own code fails its tests" >"$t/title"
out=$(go env BUILD=success RESULT=fail REPORT="$t/report")
[[ $out == "gh issue edit 12 "* && $out != *"issue comment"* ]] || fail "the same state commented on again: $out"
rm "$t/title"
[[ $(go env BUILD=success RESULT=fail REPORT="$t/report") == *"gh issue comment 12 "* ]] || fail "a title not read: no comment"
echo "Heads-up: x" >"$t/title"; touch "$t/commentfail"
! said env BUILD=success RESULT=fail REPORT="$t/report" || fail "the comment couldn't be written, and the report job passed"
[[ $(grep -c '^gh issue comment' "$t/gh.log") == 3 ]] || fail "the comment not tried three times: $(cat "$t/gh.log")"
rm -f "$t/commentfail" "$t/title" "$t/open"
echo "ok ci-report"
