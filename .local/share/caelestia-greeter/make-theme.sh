#!/usr/bin/env bash
# Writes theme.json (Caelestia's current colours + user) and copies the current wallpaper
# into the given folder, for the login screen in that folder.
#   usage: make-theme.sh <folder> [user]   (user: whoever runs it, by default)
set -euo pipefail
dir=$1
user=${2:-$(id -un)}
home=$(getent passwd "$user" | cut -d: -f6)
scheme="$home/.local/state/caelestia/scheme.json"
wall=$(cat "$home/.local/state/caelestia/wallpaper/path.txt" 2>/dev/null || true)

mkdir -p "$dir"
# (a picture only: Caelestia's wallpaper can be a video, which the login screen can't show; the last picture stays)
if [[ -f $wall && $(file -b --mime-type "$wall") == image/* ]]; then
    install -m 644 "$wall" "$dir/wallpaper"
fi
# No colours yet (Caelestia hasn't written them): the login screen's own defaults, but still for this user
colours=$(jq -c '.colours // {}' "$scheme" 2>/dev/null) || true
[[ -n $colours ]] || colours='{}'  # an empty file prints nothing
jq -n --arg user "$user" --arg wall "$dir/wallpaper" --argjson colours "$colours" \
    '{user: $user, wallpaper: $wall, colours: $colours}' >"$dir/theme.json.tmp"
mv "$dir/theme.json.tmp" "$dir/theme.json"  # whole or not at all: an empty one would leave the login screen with no user
chmod 644 "$dir/theme.json"
