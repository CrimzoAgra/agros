#!/usr/bin/env bash
# ci/report.sh: one issue for what CI held back; opened, then edited, never a second one; closed once a run puts
# everything out again; nothing done when all went out and none was open. gh is a stand-in
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho "gh $*" >>%s/gh.log\ncase "$1 $2" in "issue list") cat %s/open 2>/dev/null; true ;; "issue create"|"issue edit") for a; do [[ $p == --body-file ]] && cp "$a" %s/body; p=$a; done ;; esac\n' \
    "$t" "$t" "$t" >"$t/bin/gh"
chmod +x "$t/bin/gh"
go() { rm -f "$t/gh.log"; PATH=$t/bin:$PATH RUN_URL=https://run "$@" "$here/ci/report.sh" >/dev/null; grep -v '^gh issue list\|^gh label' "$t/gh.log" || true; }
echo "quickshell-git: AgrOS's fix didn't build" >"$t/held"
[[ $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held") == "gh issue create --label held --title Held back: built and tested, but some packages didn't build --body-file "* ]] ||
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
# Upstream's next release no longer fitting (the report's AHEAD lines): all went out, but the issue opened, said as a
# heads-up, kept open while it lasts, closed once it's gone
printf -- '- With this run'"'"'s [agros], on today'"'"'s Arch:\n    all passed\n- Upstream'"'"'s next release...:\n    AHEAD lutris-overlay: x\n' >"$t/report"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue create --label held --title Heads-up: upstream's next release no longer fits AgrOS's changes --body-file "* ]] ||
    fail "upstream's next release not fitting didn't open an issue: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
grep -q 'AHEAD lutris-overlay: x' "$t/body" || fail "the issue doesn't say what doesn't fit: $(cat "$t/body")"
echo 13 >"$t/open"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue edit 13 --title Heads-up: "* ]] ||
    fail "the heads-up closed while it lasts: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
[[ $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" REPORT="$t/report") == "gh issue edit 13 --title Held back: built and tested, but some packages didn't build --body-file "* ]] ||
    fail "a hold not said over the heads-up: $(go env BUILD=success RELEASE=success RESULT=ok HELD="$t/held" REPORT="$t/report")"
sed -i '/AHEAD/d' "$t/report"
[[ $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report") == "gh issue close 13 "* ]] ||
    fail "the heads-up not closed once it's gone: $(go env BUILD=success RELEASE=success RESULT=ok REPORT="$t/report")"
echo "ok ci-report"
