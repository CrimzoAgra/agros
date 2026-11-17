#!/usr/bin/env bash
# Writes theme.json (Caelestia's current colours + user) and copies the current wallpaper
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
if [[ -f $wall && $(file -b --mime-type "$wall") == image/* ]]; then
    install -m 644 "$wall" "$dir/wallpaper"
fi
# No colours yet (Caelestia hasn't written them): the login screen's own defaults, but still for this user
colours=$(jq -c '.colours // {}' "$scheme" 2>/dev/null) || true
[[ -n $colours ]] || colours='{}'  # an empty file prints nothing
# A new file of its own, then renamed over theme.json: whole or not at all (an empty one would leave the login screen
# with no user). Not a fixed name: the theme folder is every admin's (wheel, no sticky bit), so two logins at once wrote
# into one file, and a link left at that name by another account was written through
tmp=$(mktemp "$dir/theme.json.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq -n --arg user "$user" --arg wall "$dir/wallpaper" --argjson colours "$colours" \
    '{user: $user, wallpaper: $wall, colours: $colours}' >"$tmp"
chmod 644 "$tmp"
mv "$tmp" "$dir/theme.json"
