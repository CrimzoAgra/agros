#!/usr/bin/env bash
# The login screen's theme.json: Caelestia's colours and the user, and still the user when there are no colours yet
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
"$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody || fail "no colours stopped it"   # nobody: no Caelestia state
[[ $(jq -r '.user + " " + (.colours | type)' "$t/a/theme.json") == "nobody object" ]] || fail "theme without colours: $(cat "$t/a/theme.json")"
# Made in a file of its own, never through a link at the old fixed name (the theme folder is shared by every admin), and
# none left behind; readable by the login screen's account
ln -s "$t/victim" "$t/a/theme.json.tmp"
"$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody || fail "a second run failed"
[[ ! -e $t/victim ]] || fail "theme.json written through a link left in the theme folder"
[[ $(stat -c %a "$t/a/theme.json") == 644 ]] || fail "theme.json isn't readable by all: $(stat -c %a "$t/a/theme.json")"
[[ -z $(find "$t/a" -name 'theme.json.?*' ! -name theme.json.tmp) ]] || fail "temporary files left: $(ls "$t/a")"
if [[ -f $HOME/.local/state/caelestia/scheme.json ]]; then
    "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/b"
    (($(jq '.colours | length' "$t/b/theme.json") > 0)) || fail "colours not copied"
fi
echo "ok greeter-theme"
