#!/usr/bin/env bash
# setup/modules/10-keyboard.sh: with nothing to read (no terminal, run from a script) the layout is left as it is and
# setup carries on (as ask answers no), not stopped at its first step; a typed layout is set
set -euo pipefail
. "$(dirname "$0")/lib.sh"
# (in a shell of its own with set -e on, as setup.sh runs it; sudo a stand-in that only notes what it was asked)
run() {
    log=$t/sudo.log bash -euo pipefail -c 'yes=false; sudo() { echo "$*" >>"$log"; }
        source "$1"; module_keyboard; echo "after the step"' _ "$here/setup/modules/10-keyboard.sh"
}
out=$(run </dev/null 2>&1) || fail "nothing to read stopped setup: $out"
grep -q "after the step" <<<"$out" || fail "the step didn't finish: $out"
# (said so: not "stays <layout>" on a machine with one set, which would hide it being reset to us on one without)
grep -q "left as it is" <<<"$out" || fail "nothing to read didn't leave the layout as it is: $out"
[[ ! -s $t/sudo.log ]] || fail "nothing to read changed the layout: $(cat "$t/sudo.log")"
out=$(run <<<"zz" 2>&1) || fail "a typed layout failed: $out"
grep -qx "localectl set-x11-keymap zz" "$t/sudo.log" || fail "the typed layout wasn't set: $(cat "$t/sudo.log" 2>/dev/null)"
# A layout localectl refuses (a typo): said, setup goes on (set -e stopped it at its first step)
out=$(log=$t/sudo.log bash -euo pipefail -c 'yes=false; sudo() { return 1; }
        source "$1"; module_keyboard; echo "after the step"' _ "$here/setup/modules/10-keyboard.sh" <<<"ptt" 2>&1) ||
    fail "a layout localectl refused stopped setup: $out"
{ grep -q "after the step" <<<"$out" && grep -q "isn't a layout" <<<"$out"; } || fail "a refused layout not said: $out"
echo "ok setup-keyboard"
