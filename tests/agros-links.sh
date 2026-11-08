#!/usr/bin/env bash
# agros-links: a config folder new in /etc/skel reaches an existing home once, never over the user's own, and one the
# user deleted doesn't come back
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/lib/bin" "$t/lib/share" "$t/skel/.config/fetch" "$t/skel/.config/foot" "$t/home/.config/foot"
echo agros >"$t/skel/.config/fetch/config"; echo agros >"$t/skel/.config/foot/foot.ini"
echo mine >"$t/home/.config/foot/foot.ini"
run() { HOME=$t/home XDG_STATE_HOME=$t/home/.local/state AGROS_LIB=$t/lib AGROS_SKEL=$t/skel "$here/.local/bin/agros-links"; }

run
[[ $(cat "$t/home/.config/fetch/config") == agros ]] || fail "a new config not copied in"
[[ $(cat "$t/home/.config/foot/foot.ini") == mine ]] || fail "the user's own config overwritten"

rm -rf "$t/home/.config/fetch"; run
[[ ! -e $t/home/.config/fetch ]] || fail "a config the user deleted came back"
