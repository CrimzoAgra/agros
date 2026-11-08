#!/usr/bin/env bash
# The login screen's theme.json: Caelestia's colours and the user, and still the user when there are no colours yet
set -euo pipefail
. "$(dirname "$0")/lib.sh"
"$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody || fail "no colours stopped it"   # nobody: no Caelestia state
[[ $(jq -r '.user + " " + (.colours | type)' "$t/a/theme.json") == "nobody object" ]] || fail "theme without colours: $(cat "$t/a/theme.json")"
if [[ -f $HOME/.local/state/caelestia/scheme.json ]]; then
    "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/b"
    (($(jq '.colours | length' "$t/b/theme.json") > 0)) || fail "colours not copied"
fi
echo "ok greeter-theme"
