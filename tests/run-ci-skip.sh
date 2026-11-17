#!/usr/bin/env bash
# On CI (its pass approves that Hyprland for AgrOS's machines: the upstream gate) a test skipped there fails, whole
# (run.sh: its last line "skip ..." or "... SKIPPED ...") or in part (lib.sh's skipped()); elsewhere both are said and
# pass. A pass ends on the test's own ok line: one that ended early with exit 0 fails, on CI or not; one that hangs is
# stopped at its time limit and fails. run.sh and lib.sh copied beside fake tests
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir "$t/tests"
cp "$here/tests/run.sh" "$here/tests/lib.sh" "$t/tests/"
printf '#!/bin/sh\necho "skip whole (no such thing here)"\n' >"$t/tests/whole.sh"
printf '#!/bin/sh\necho "ok marked (SKIPPED: a part)"\n' >"$t/tests/marked.sh"
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/lib.sh"\nskipped "no such thing here: a part not run"\necho "ok part"\n' >"$t/tests/part.sh"
printf '#!/bin/sh\necho "ok plain"\n' >"$t/tests/plain.sh"
chmod +x "$t/tests/"*.sh
for x in whole marked part; do
    out=$(env -u CI bash "$t/tests/run.sh" "$x") || fail "$x skipped off CI failed: $out"
    out=$(CI=1 bash "$t/tests/run.sh" "$x") && fail "$x skipped on CI passed: $out"
    [[ $out == "FAIL $x: "* ]] || fail "$x skipped on CI not said as a failure: $out"
done
out=$(CI=1 bash "$t/tests/run.sh" plain) && [[ $out == "ok plain" ]] || fail "a plain pass on CI not one: $out"
# Several at once: said in order; two that clash when run together (one marker file) pass, each run again alone; a real
# failure still fails
for n in a b; do
    printf '#!/bin/sh\nif [ -e %q/busy ]; then echo "FAIL: clash"; exit 1; fi\ntouch %q/busy; sleep 1; rm -f %q/busy\necho "ok clash-%s"\n' \
        "$t" "$t" "$t" "$n" >"$t/tests/clash-$n.sh"
done
chmod +x "$t/tests/"*.sh
out=$(CI=1 AGROS_TEST_JOBS=3 bash "$t/tests/run.sh" clash-a plain clash-b) && [[ $out == $'ok clash-a\nok plain\nok clash-b' ]] ||
    fail "tests run together: not each passed, in order: $out"
# One that failed among the others and passed alone passes, said on stderr (a flaky test, seen in CI's log)
printf '#!/bin/sh\nif [ ! -e %q/once ]; then touch %q/once; echo "FAIL: first time"; exit 1; fi\necho "ok flaky"\n' \
    "$t" "$t" >"$t/tests/flaky.sh"
chmod +x "$t/tests/flaky.sh"
out=$(AGROS_TEST_JOBS=3 bash "$t/tests/run.sh" plain flaky 2>"$t/err") && [[ $out == $'ok plain\nok flaky' ]] ||
    fail "a test that passed alone didn't pass: $out"
grep -xF '!! flaky failed among the others, passed alone: first time' "$t/err" >/dev/null ||
    fail "a test that failed among the others not said: $(cat "$t/err")"
out=$(CI=1 AGROS_TEST_JOBS=3 bash "$t/tests/run.sh" plain whole) && fail "a real failure among others passed: $out"
[[ $out == $'ok plain\nFAIL whole: '* ]] || fail "a real failure among others not said in order: $out"
# Ended with exit 0 before its ok line: something said last, another test's line last, nothing at all
printf '#!/bin/sh\necho "checking"\nexit 0\necho "ok early"\n' >"$t/tests/early.sh"
printf '#!/bin/sh\necho "ok plain"\n' >"$t/tests/other.sh"
printf '#!/bin/sh\n' >"$t/tests/silent.sh"
chmod +x "$t/tests/"*.sh
for x in early other silent; do
    out=$(env -u CI bash "$t/tests/run.sh" "$x") && fail "$x, ended without its ok line, passed: $out"
    [[ $out == "FAIL $x: it ended without its \"ok $x\" line: "* ]] || fail "$x ended without its ok line, not said: $out"
done
out=$(AGROS_TEST_JOBS=3 bash "$t/tests/run.sh" plain silent) && fail "one without its ok line among others passed: $out"
[[ $out == $'ok plain\nFAIL silent: '* ]] || fail "one without its ok line among others not said in order: $out"
# One that hangs, with what it started holding the output too: stopped at its time limit, said, and run.sh not kept
# waiting by either (alone, and among others)
printf '#!/bin/sh\necho "waiting"\nsleep 300 &\nsleep 300\necho "ok hang"\n' >"$t/tests/hang.sh"
chmod +x "$t/tests/hang.sh"
start=$SECONDS
out=$(AGROS_TEST_TIMEOUT=1 bash "$t/tests/run.sh" hang) && fail "a test that hung passed: $out"
[[ $out == "FAIL hang: stopped at its time limit (1s; its last line: waiting)" ]] || fail "a hung test not said: $out"
out=$(AGROS_TEST_TIMEOUT=1 AGROS_TEST_JOBS=3 bash "$t/tests/run.sh" plain hang) && fail "a test that hung among others passed: $out"
[[ $out == $'ok plain\nFAIL hang: stopped at its time limit'* ]] || fail "a hung test among others not said in order: $out"
((SECONDS - start < 30)) || fail "a hung test, or what it started, kept run.sh waiting: $((SECONDS - start))s"
echo "ok run-ci-skip"
