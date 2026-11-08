#!/usr/bin/env bash
# agros-links: a config file new in /etc/skel reaches an existing home once (inside a folder the user already has too),
# never over the user's own, and one the user deleted doesn't come back
set -euo pipefail
. "$(dirname "$0")/lib.sh"
s=$t/skel/.config h=$t/home/.config
mkdir -p "$t/lib/bin" "$t/lib/share" "$s/fetch" "$s/foot" "$s/librewolf/librewolf" "$h/foot" "$h/librewolf/librewolf/x.default"
echo agros >"$s/fetch/config"; echo agros >"$s/foot/foot.ini"; echo agros >"$s/librewolf/librewolf/librewolf.overrides.cfg"
echo mine >"$h/foot/foot.ini"
run() { HOME=$t/home XDG_STATE_HOME=$t/home/.local/state AGROS_LIB=$t/lib AGROS_SKEL=$t/skel "$here/.local/bin/agros-links"; }

run
[[ $(cat "$h/fetch/config") == agros ]] || fail "a new config not copied in"
[[ $(cat "$h/librewolf/librewolf/librewolf.overrides.cfg") == agros ]] || fail "a new file in a folder the user has not copied in"
[[ $(cat "$h/foot/foot.ini") == mine ]] || fail "the user's own config overwritten"

rm -rf "$h/fetch"; run
[[ ! -e $h/fetch ]] || fail "a config the user deleted came back"
