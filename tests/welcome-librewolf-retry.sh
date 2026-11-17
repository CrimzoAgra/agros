#!/usr/bin/env bash
# agros-welcome's LibreWolf step: offline at the first login, its theme (Lagoon, from addons.mozilla.org) didn't
# download and the step still counted as done, never tried again. Now it's tried again at the next login (the settings
# not applied a second time), a third failure in a row counted as done; online, the theme is put in and turned on
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
h=$t/home sb=$t/bin prof=$t/home/.config/librewolf/librewolf/x.default
mkdir -p "$sb" "$prof" "$h/.local/share/firefox"
printf '[Profile0]\nName=default\nIsRelative=1\nPath=x.default\nDefault=1\n' >"$h/.config/librewolf/librewolf/profiles.ini"
: >"$prof/prefs.js"
echo 'user_pref("agros.test", true);' >"$h/.local/share/firefox/settings.js"
printf '#!/bin/sh\nexit 1\n' >"$sb/pgrep"   # (no LibreWolf open)
printf '#!/bin/sh\nexit 1\n' >"$sb/curl"    # (offline)
printf '#!/bin/sh\nexit 0\n' >"$sb/librewolf"
chmod +x "$sb"/*
run() { HOME=$h PATH=$sb:$PATH bash -c 'source "$1"; librewolf_setup' _ "$here/.local/bin/agros-welcome" >/dev/null 2>&1; }
applied() { grep -c '^user_pref("agros.test"' "$prof/prefs.js"; }

run && fail "offline, the LibreWolf step counted as done: its theme never tried again"
[[ $(applied) == 1 ]] || fail "LibreWolf's settings not applied once"
run && fail "offline a second login in a row, the LibreWolf step counted as done"
[[ $(applied) == 1 ]] || fail "LibreWolf's settings applied again on the retry"
run || fail "the theme failing a third login in a row not counted as done"

# Online: downloaded, registered by LibreWolf's start (its extensions.json), then the theme in use
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { echo xpi >"$2"; exit 0; }; shift; done\nexit 1\n' >"$sb/curl"
printf '#!/bin/sh\necho %s >%q\n' \
    "'{\"addons\":[{\"id\":\"default-theme@mozilla.org\",\"type\":\"theme\",\"active\":true},{\"id\":\"nova-lagoon@mozilla.org\",\"type\":\"theme\",\"active\":false}]}'" \
    "$prof/extensions.json" >"$sb/librewolf"
run || fail "online, the LibreWolf step failed"
[[ -s $prof/extensions/nova-lagoon@mozilla.org.xpi ]] || fail "the theme not put in the profile"
[[ $(jq -r '.addons[] | select(.active) | .id' "$prof/extensions.json") == nova-lagoon@mozilla.org ]] ||
    fail "the theme not the one in use: $(cat "$prof/extensions.json")"
[[ $(applied) == 1 ]] || fail "LibreWolf's settings applied again once the theme came"
echo "ok welcome-librewolf-retry"
