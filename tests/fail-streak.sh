#!/usr/bin/env bash
# fail-streak: one more failure in a row counted per <what>; another <what> starts again at 1, as does a file that
# isn't its own (a corrupt or hand-edited count)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
fs() { "$here/.local/bin/fail-streak" "$t/state/streak" "$@"; }
[[ $(fs a; fs a; fs a) == $'1\n2\n3' ]] || fail "not counted up"
[[ $(fs b) == 1 ]] || fail "another <what> not started again"
[[ $(fs a) == 1 ]] || fail "back to the first <what> not started again"
[[ $(fs; fs) == $'1\n2' ]] || fail "with no <what>"
printf 'a\tlots\n' >"$t/state/streak"
[[ $(fs a) == 1 ]] || fail "a corrupt count not started again"
printf 'garbage' >"$t/state/streak"
[[ $(fs a; fs a) == $'1\n2' ]] || fail "a file not its own not started again"
echo "ok fail-streak"
