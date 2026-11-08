#!/usr/bin/env bash
# setup asks for your password once, up front, when a step that changes the system will run (not for the steps in your
# home alone), and keeps sudo fresh in the background (its own timeout asked again along a 15 min run); the refresher
# ends with setup
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$t/bin" "$t/home"
printf '#!/bin/sh\necho "$*" >>"%s/sudo.log"\n' "$t" >"$t/bin/sudo"
for s in systemctl gtk-update-icon-cache; do printf '#!/bin/sh\nexit 0\n' >"$t/bin/$s"; done
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH SUDO_REFRESH=0.2 HOME=$t/home XDG_STATE_HOME='' XDG_CONFIG_HOME=''
lines() { wc -l <"$t/sudo.log" 2>/dev/null || echo 0; }
stopped() {  # the refresher gone with setup: no more refreshes
    local n
    sleep 0.3  # (one already under way)
    n=$(lines); sleep 0.8
    [[ $(lines) == "$n" ]]
}

# A system step (the keyboard, nothing to answer: left as it is): asked once, then refreshed while it runs
"$here/setup.sh" --only keyboard </dev/null >"$t/out" 2>&1 || fail "setup failed: $(cat "$t/out")"
[[ $(head -1 "$t/sudo.log") == "-v" ]] || fail "the password not asked up front: $(cat "$t/sudo.log" 2>/dev/null)"
stopped || fail "sudo still refreshed after setup ended"
# The refresher itself, in a longer run: refreshed without asking (-n), and gone once the run is
: >"$t/sudo.log"
bash -c 'source "$1/setup/lib.sh"; sudo_keepalive; sleep 1' _ "$here"
[[ $(grep -cx -- "-n -v" "$t/sudo.log") -ge 2 ]] || fail "sudo not kept fresh: $(cat "$t/sudo.log")"
stopped || fail "the refresher outlived its run"
# Only the steps in your home: no password
: >"$t/sudo.log"
"$here/setup.sh" --only files </dev/null >"$t/out" 2>&1 || fail "setup's files step failed: $(cat "$t/out")"
[[ ! -s $t/sudo.log ]] || fail "sudo asked for with only the steps in your home: $(cat "$t/sudo.log")"
echo "ok setup-sudo"
