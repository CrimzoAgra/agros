#!/usr/bin/env bash
# setup.sh with stand-in steps: --list, --user-only runs only the home steps, --only needs a step, --only with
# --user-only is refused, a failing command stops its step (and the run) and says which step; ask with nothing to read
# answers no
set -uo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/setup/modules"; cp "$here/setup.sh" "$t/"; cp "$here/setup/lib.sh" "$t/setup/"
# (sudo a stand-in: a system step here asks for the password up front, and the real one would ask the terminal)
mkdir -p "$t/bin"; printf '#!/bin/sh\necho "$*" >>"%s/sudo.log"\n' "$t" >"$t/bin/sudo"; chmod +x "$t/bin/sudo"
export PATH=$t/bin:$PATH
printf '# about: one\n# scope: user\nmodule_one() { echo one ran; }\n' >"$t/setup/modules/10-one.sh"
printf '# about: two\n# scope: user\nmodule_two() { echo two ran; }\n' >"$t/setup/modules/20-two.sh"
printf '# about: three\n# scope: system\nmodule_three() { echo three ran; }\n' >"$t/setup/modules/30-three.sh"
out=$("$t/setup.sh" --list 2>&1) || fail "--list failed: $out"
grep -q "^three *system *three" <<<"$out" || fail "--list: $out"
out=$("$t/setup.sh" -y --user-only 2>&1) || fail "--user-only failed: $out"
grep -q "one ran" <<<"$out" && grep -q "two ran" <<<"$out" && ! grep -q "three ran" <<<"$out" || fail "--user-only ran the wrong steps: $out"
out=$("$t/setup.sh" --only 2>&1) && fail "--only with no step ran"
grep -q "needs at least one step" <<<"$out" || fail "--only alone: $out"
out=$("$t/setup.sh" -y --only two 2>&1) || fail "--only two failed: $out"
grep -q "two ran" <<<"$out" && ! grep -q "one ran" <<<"$out" || fail "--only two ran the wrong steps: $out"
# --only=<step>[,<step>] as --only <step>...; an unknown option named, then the usage
out=$("$t/setup.sh" -y --only=two 2>&1) || fail "--only=two failed: $out"
{ grep -q "two ran" <<<"$out" && ! grep -q "one ran" <<<"$out"; } || fail "--only=two ran the wrong steps: $out"
out=$("$t/setup.sh" -y --only=one,two 2>&1) || fail "--only=one,two failed: $out"
{ grep -q "one ran" <<<"$out" && grep -q "two ran" <<<"$out" && ! grep -q "three ran" <<<"$out"; } || fail "--only=one,two: $out"
out=$("$t/setup.sh" --only= 2>&1) && fail "--only= with no step ran"
out=$("$t/setup.sh" --bogus 2>&1) && fail "an unknown option reported success"
[[ $out == "unknown option: --bogus"*"--only <step>"* ]] || fail "an unknown option not named before the usage: $out"
"$t/setup.sh" --only two --user-only >/dev/null 2>&1 && fail "--only with --user-only accepted"
printf '# about: one\n# scope: user\nmodule_one() { echo one ran; false; echo after-failure; }\n' >"$t/setup/modules/10-one.sh"
out=$("$t/setup.sh" -y 2>&1) && fail "a failing step reported success"
grep -q "after-failure" <<<"$out" && fail "a failing command didn't stop its step"
grep -q "two ran" <<<"$out" && fail "steps after a failed one ran"
grep -q "The one step failed" <<<"$out" || fail "the failed step wasn't named: $out"
# ask: Enter is yes, n is no, and nothing to read (no terminal, started from a script) is no, not yes to everything
(yes=false; source "$t/setup/lib.sh"; ask "Keep it?" <<<"") >/dev/null 2>&1 || fail "ask with Enter said no"
(yes=false; source "$t/setup/lib.sh"; ask "Remove it?" <<<"n") >/dev/null 2>&1 && fail "ask answered n said yes"
(yes=false; source "$t/setup/lib.sh"; ask "Remove it?" </dev/null) >/dev/null 2>&1 && fail "ask with nothing to read said yes"
echo "ok setup-args"
