#!/usr/bin/env bash
# On CI (its pass approves that Hyprland for AgrOS's machines: the upstream gate) a test skipped there fails, whole
# (run.sh: its last line "skip ..." or "... SKIPPED ...") or in part (lib.sh's skipped()); elsewhere both are said and
# pass. run.sh and lib.sh copied beside fake tests
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
echo "ok run-ci-skip"
