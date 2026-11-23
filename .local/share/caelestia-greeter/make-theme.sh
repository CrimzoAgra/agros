#!/usr/bin/env bash
# Writes theme.json (Caelestia's current colours, user and main screen) and copies the current wallpaper
# into the given folder, for the login screen in that folder. Run at every login by greeter-theme-sync (into
# /etc/greetd/caelestia-greeter/theme), and by agros-greeter's install for a first theme (as the user it shows).
#   usage: make-theme.sh <folder> [user]   (user: whoever runs it, by default)
set -euo pipefail
dir=$1
user=${2:-$(id -un)}
home=$(getent passwd "$user" | cut -d: -f6)
scheme="$home/.local/state/caelestia/scheme.json"
wall=$(cat "$home/.local/state/caelestia/wallpaper/path.txt" 2>/dev/null || true)

mkdir -p "$dir"
# (a picture only: Caelestia's wallpaper can be a video, which the login screen can't show; the last picture stays)
# (not copied again when it's the same: this runs at every config reload too)
if [[ -f $wall && $(file -b --mime-type "$wall") == image/* ]] && ! cmp -s "$wall" "$dir/wallpaper"; then
    install -m 644 "$wall" "$dir/wallpaper"
fi
# The main screen, for the login card to go on: the Settings app's (screens.main), else the one with workspace 1 (the
# main screen's), by its connector and model (all the login screen knows of a screen). Only from inside Hyprland: else
# (agros-greeter's install) the last one stays
screen=$(jq -c '.screen // null' "$dir/theme.json" 2>/dev/null) || true
if mons=$(hyprctl -j monitors 2>/dev/null) && [[ $mons == '['* ]]; then
    main=$(jq -r '."screens.main" // "" | strings' "$home/.config/dots/settings.json" 2>/dev/null) || main=
    ws1=$(hyprctl -j workspaces 2>/dev/null | jq -r '.[] | select(.id == 1) | .monitor' 2>/dev/null) || ws1=
    screen=$(jq -c --arg d "$main" --arg w "$ws1" '[(.[] | select($d != "" and .description == $d)),
        (.[] | select(.name == $w))] | first // null | if . then {name, model} else null end' <<<"$mons") || screen=null
fi
[[ -n $screen ]] || screen=null
# No colours yet (Caelestia hasn't written them): the login screen's own defaults, but still for this user
colours=$(jq -c '.colours // {}' "$scheme" 2>/dev/null) || true
[[ -n $colours ]] || colours='{}'  # an empty file prints nothing
# A new file of its own, then renamed over theme.json: whole or not at all (an empty one would leave the login screen
# with no user). Not a fixed name: the theme folder is every admin's (wheel, no sticky bit), so two logins at once wrote
# into one file, and a link left at that name by another account was written through
tmp=$(mktemp "$dir/theme.json.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq -n --arg user "$user" --arg wall "$dir/wallpaper" --argjson colours "$colours" --argjson screen "$screen" \
    '{user: $user, wallpaper: $wall, colours: $colours, screen: $screen}' >"$tmp"
chmod 644 "$tmp"
mv "$tmp" "$dir/theme.json"
