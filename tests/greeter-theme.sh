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
# The screens' layout for the login screen's compositor: each one's turn, scale and place, the places the Settings app
# saved when every screen has one (the desktop's have monitors.lua's gap), else Hyprland's
cat >"$t/bin/hyprctl" <<'EOF'
#!/bin/sh
case $2 in
monitors) echo '[{"name":"DP-1","model":"Big","description":"X Big 1","x":0,"y":280,"transform":0,"scale":1},
{"name":"HDMI-A-1","model":"Small","description":"Y Small 2","x":2624,"y":0,"transform":3,"scale":1.25}]' ;;
workspaces) echo '[{"id":1,"monitor":"HDMI-A-1"}]' ;;
esac
EOF
echo '{"screens.X Big 1.position":"0x280","screens.Y Small 2.position":"2560x0","screens.main":"X Big 1"}' >"$t/settings.json"
DOTS_SETTINGS_JSON=$t/settings.json PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ $(jq -c '.screen, [.screens[] | [.name, .transform, .scale, .x, .y]]' "$t/a/theme.json") == $'{"name":"DP-1","model":"Big"}\n[["DP-1",0,1,0,280],["HDMI-A-1",3,1.25,2560,0]]' ]] ||
    fail "the screens' layout (saved places, no gap): $(jq -c '.screen, .screens' "$t/a/theme.json")"
# Each screen's own wallpaper (the Settings app's) beside the main one, its path in its entry; one no longer its own gone
# (a 1x1 PNG)
base64 -d >"$t/own.png" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
echo text >"$t/not-a-picture"
echo '{"screens.X Big 1.wallpaper":"'"$t"'/own.png","screens.Y Small 2.wallpaper":"'"$t"'/not-a-picture"}' >"$t/settings.json"
DOTS_SETTINGS_JSON=$t/settings.json PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ $(jq -c '[.screens[] | [.name, .wallpaper]]' "$t/a/theme.json") == '[["DP-1","'"$t"'/a/wallpaper-DP-1"],["HDMI-A-1",null]]' ]] &&
    cmp -s "$t/own.png" "$t/a/wallpaper-DP-1" && [[ ! -e $t/a/wallpaper-HDMI-A-1 ]] ||
    fail "a screen's own wallpaper not beside the main one, or a file not a picture taken: $(jq -c .screens "$t/a/theme.json")"
echo '{}' >"$t/settings.json"
DOTS_SETTINGS_JSON=$t/settings.json PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ ! -e $t/a/wallpaper-DP-1 && $(jq -c '[.screens[].wallpaper]' "$t/a/theme.json") == '[null,null]' ]] ||
    fail "a screen's own wallpaper left after it went back to the main one: $(ls "$t/a")"
echo '{"screens.X Big 1.position":"0x280"}' >"$t/settings.json"
DOTS_SETTINGS_JSON=$t/settings.json PATH=$t/bin:$PATH "$here/.local/share/caelestia-greeter/make-theme.sh" "$t/a" nobody
[[ $(jq -c '[.screens[] | [.x, .y]]' "$t/a/theme.json") == '[[0,280],[2624,0]]' ]] ||
    fail "a screen with no saved place: not Hyprland's places: $(jq -c .screens "$t/a/theme.json")"
# best-mode, in the login screen's compositor: those set with wlr-randr in one call, by connector and model (a
# different monitor on a connector since: left alone)
mkdir -p "$t/g/theme"
cp "$here/.local/share/caelestia-greeter/best-mode" "$here/.local/share/caelestia-greeter/screenmode.py" "$t/g/"
cp "$t/a/theme.json" "$t/g/theme/theme.json"
cat >"$t/bin/wlr-randr" <<EOF
#!/bin/sh
if [ "\$1" = --json ]; then
    echo '[{"name":"DP-1","model":"Big","modes":[{"width":2560,"height":1440,"refresh":60.0,"preferred":true,"current":true}]},
{"name":"HDMI-A-1","model":"Other","modes":[{"width":1920,"height":1080,"refresh":60.0,"preferred":true,"current":true}]}]'
else
    echo "\$*" >>"$t/randr"
fi
EOF
chmod +x "$t/bin/wlr-randr"
PATH=$t/bin:$PATH python3 "$t/g/best-mode" >/dev/null
[[ $(cat "$t/randr") == "--output DP-1 --transform normal --pos 0,280 --scale 1" ]] ||
    fail "best-mode's layout: $(cat "$t/randr")"
sed -i 's/"Other"/"Small"/' "$t/bin/wlr-randr"
: >"$t/randr"
PATH=$t/bin:$PATH python3 "$t/g/best-mode" >/dev/null
[[ $(cat "$t/randr") == "--output DP-1 --transform normal --pos 0,280 --scale 1 --output HDMI-A-1 --transform 270 --pos 2624,0 --scale 1.25" ]] ||
    fail "best-mode's layout, both screens: $(cat "$t/randr")"
echo "ok greeter-theme"
