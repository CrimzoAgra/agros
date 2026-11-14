#!/usr/bin/env bash
# agros-welcome's Equibop theme: an empty settings.json started as {} with the theme (json-edit leaves an empty file
# alone: the theme was never added, the step marked done all the same); one it can't write fails the step
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
h=$t/home sb=$t/bin; mkdir -p "$h/.config/equibop/settings" "$sb"
printf '#!/bin/sh\nexit 0\n' >"$sb/equibop"; chmod +x "$sb/equibop"
eq=$h/.config/equibop/settings/settings.json
others() {
    HOME=$h PATH=$sb:$PATH bash -c 'source "$1"; window_buttons() { :; }; installed() { false; }; others' _ \
        "$here/.local/bin/agros-welcome" >/dev/null 2>&1
}
: >"$eq"
others || fail "an empty settings.json failed the step"
[[ $(jq -c .enabledThemes "$eq") == '["caelestia.theme.css"]' ]] || fail "an empty settings.json: no theme: $(cat "$eq")"
echo '{broken' >"$eq"
others && fail "a settings.json the theme couldn't be added to: the step marked done"
echo "ok welcome-equibop"
