#!/usr/bin/env bash
# The login screen's theme.json: Caelestia's colours and the user, and still the user when there are no colours yet;
# the main screen the login card goes on
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
# The main screen for the login card (no Settings app choice: nobody has no home): the one with workspace 1, by
# connector and model; outside Hyprland (no hyprctl answer) the last one kept
mkdir -p "$t/bin"
cat >"$t/bin/hyprctl" <<'EOF'
#!/bin/sh
case $2 in
monitors) echo '[{"name":"DP-1","model":"Big","description":"X Big 1"},{"name":"HDMI-A-1","model":"Small","description":"Y Small 2"}]' ;;
workspaces) echo '[{"id":1,"monitor":"HDMI-A-1"},{"id":11,"monitor":"DP-1"}]' ;;
esac
EOF
chmod +x "$t/bin/hyprctl"
PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ $(jq -c .screen "$t/a/theme.json") == '{"name":"HDMI-A-1","model":"Small"}' ]] ||
    fail "the main screen not the one with workspace 1: $(jq -c .screen "$t/a/theme.json")"
printf '#!/bin/sh
exit 1
' >"$t/bin/hyprctl"
PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ $(jq -c .screen "$t/a/theme.json") == '{"name":"HDMI-A-1","model":"Small"}' ]] ||
    fail "outside Hyprland the main screen was lost: $(jq -c .screen "$t/a/theme.json")"
echo "ok greeter-theme"
