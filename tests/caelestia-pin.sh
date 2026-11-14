#!/usr/bin/env bash
# caelestia-pin <dock> <app id> (the dock's and the Super menu's pin buttons): pins and unpins, keeps the rest of
# shell.json, loses no click of several at once, and starts a pins file that isn't a list again
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
pin() { HOME=$t "$here/.local/bin/caelestia-pin" "$@"; }
pins=$t/.config/quickshell/sidedock/pins.json shell=$t/.config/caelestia/shell.json

pin dock firefox; pin dock foot
[[ $(jq -c . "$pins") == '["firefox","foot"]' ]] || fail "dock pins: $(cat "$pins")"
pin dock firefox
[[ $(jq -c . "$pins") == '["foot"]' ]] || fail "dock unpin: $(cat "$pins")"

# Several clicks at once: every one lands
for i in 1 2 3 4 5 6; do pin dock "app$i" & done; wait
[[ $(jq length "$pins") == 7 ]] || fail "clicks at once lost one: $(cat "$pins")"

# A hand edit that isn't a list: started again
echo '{"a": 1}' >"$pins"
pin dock foot
[[ $(jq -c . "$pins") == '["foot"]' ]] || fail "a pins file that isn't a list: $(cat "$pins")"
# An empty one: started again as [], not every pin refused
: >"$pins"
pin dock foot
[[ $(jq -c . "$pins") == '["foot"]' ]] || fail "an empty pins file: $(cat "$pins")"


# The dock's drag to reorder: the order written, under the pin clicks' lock (waits for one under way, merged with what
# it wrote), and only a list
# (the one under way changes the file as it ends: not waited for, the order went first and that change over it)
pin dock firefox
hold=$(mktemp -u)
flock "$pins.lock" sh -c "touch '$hold'; sleep 1; echo '[\"foot\", \"firefox\", \"zed\"]' >'$pins'" & holder=$!
for _ in {1..50}; do [[ -e $hold ]] && break; sleep 0.05; done
pin dock --order '["firefox", "foot"]'
wait $holder; rm -f "$hold"
[[ $(jq -c . "$pins") == '["firefox","foot","zed"]' ]] || fail "the dock's order not written after the change under way: $(cat "$pins")"
echo '["firefox", "foot"]' >"$pins"
pin dock --order '{"not": "a list"}' 2>/dev/null && fail "something not a list taken as the order"
[[ $(jq -c . "$pins") == '["firefox","foot"]' ]] || fail "something not a list written as the order: $(cat "$pins")"
# Two JSON documents (only the last one judged before): refused, the pins as they were
pin dock --order '["a"] ["b"]' 2>/dev/null && fail "two JSON documents taken as the order"
[[ $(jq -c . "$pins") == '["firefox","foot"]' ]] || fail "two JSON documents written: $(cat "$pins")"
# Merged with the pins as they are now: a pin landed since the dock's drag kept (after), one unpinned since not back
pin dock thunar; pin dock firefox   # (since the drag: thunar pinned, firefox unpinned)
pin dock --order '{"order": ["foot", "firefox"], "keys": {"firefox": "firefox", "foot": "foot"}}' r1:1
[[ $(jq -c . "$pins") == '["foot","thunar"]' ]] || fail "the order not merged with the pins as they are now: $(cat "$pins")"
# A pin stored by another name than the dock's entry id ("Spotify": com.spotify.Client): matched, written by entry id,
# not moved to the end as one pinned since
echo '["Spotify", "kitty", "foot"]' >"$pins"
pin dock --order '{"order": ["kitty", "com.spotify.Client", "foot"], "keys": {"Spotify": "com.spotify.Client", "kitty": "kitty", "foot": "foot"}}' r1:2
[[ $(jq -c . "$pins") == '["kitty","com.spotify.Client","foot"]' ]] || fail "a pin by another name not matched: $(cat "$pins")"
# An open window dropped among the pins (pinned by the drag itself): kept
echo '["foot"]' >"$pins"
pin dock --order '{"order": ["foot", "firefox"], "keys": {"foot": "foot"}}' r1:3
[[ $(jq -c . "$pins") == '["foot","firefox"]' ]] || fail "a window dropped among the pins not pinned: $(cat "$pins")"
# An older drag of the same dock run finishing after a newer one: left out; another run's: taken
pin dock --order '["firefox", "foot"]' r1:5
pin dock --order '["foot", "firefox"]' r1:4 2>/dev/null
[[ $(jq -c . "$pins") == '["firefox","foot"]' ]] || fail "an older drag's order overwrote a newer one: $(cat "$pins")"
pin dock --order '["foot", "firefox"]' r2:1
[[ $(jq -c . "$pins") == '["foot","firefox"]' ]] || fail "a new dock run's order not taken: $(cat "$pins")"
# A drag whose order couldn't be written (a pins file it can't read): not noted as the newest, the next one taken
echo '[1]' >"$pins"
pin dock --order '["foot"]' r2:9 2>/dev/null && fail "an order that couldn't be written reported success"
echo '["foot", "firefox"]' >"$pins"
pin dock --order '["firefox", "foot"]' r2:2
[[ $(jq -c . "$pins") == '["firefox","foot"]' ]] || fail "a failed write noted as the newest order: $(cat "$pins")"
# Super menu favourites: in Caelestia's shell.json, its other settings kept
mkdir -p "${shell%/*}"
echo '{"bar": {"x": 1}, "launcher": {"favouriteApps": ["foot"], "y": 2}}' >"$shell"
pin x thunar
[[ $(jq -c . "$shell") == '{"bar":{"x":1},"launcher":{"favouriteApps":["foot","thunar"],"y":2}}' ]] ||
    fail "favourites: $(cat "$shell")"
pin x foot
[[ $(jq -c .launcher.favouriteApps "$shell") == '["thunar"]' ]] || fail "favourite unpin: $(cat "$shell")"
# The weather location's writer of the same file (common/PlacePicker.qml's setLocation, the widget's and Settings':
# json-edit, as the pins) takes the same lock: a pin change under way when it writes isn't lost, nor its own
# (its command's program, whatever the arguments' layout)
grep -Eq 'execDetached\(\[[^]]*/json-edit[`"]' "$here/.config/quickshell/common/PlacePicker.qml" ||
    fail "the weather widget's writer isn't json-edit"
echo '{"launcher": {"favouriteApps": ["foot"]}}' >"$shell"
# shellcheck disable=SC2016  # (the stand-in's own)
flock "$shell.lock" sh -c 'sleep 0.6; jq ".launcher.favouriteApps += [\"thunar\"]" "$1" >"$1.tmp" && mv "$1.tmp" "$1"' _ "$shell" &
pinning=$!
sleep 0.2
# shellcheck disable=SC2016  # (jq's own variable)
"$here/.local/bin/json-edit" "$shell" --indent 4 --arg l Lisbon '.services.weatherLocation = $l'
wait $pinning
[[ $(jq -c '[.launcher.favouriteApps, .services.weatherLocation]' "$shell") == '[["foot","thunar"],"Lisbon"]' ]] ||
    fail "the weather widget's and a pin's changes to shell.json not both kept: $(cat "$shell")"
echo "ok caelestia-pin"
