#!/usr/bin/env bash
# The installed Steam games the bar's Steam menu keeps: fully installed ones from every library (a second drive's too),
# Steam's tools and half-downloaded games left out, a name with quotes read whole; no Steam at all: null (the menu
# hides nothing), and Flathub's Steam read when it's the only one
set -euo pipefail
. "$(dirname "$0")/lib.sh"
run() { HOME=$t python3 -I "$here/.local/bin/steam-installed-games"; }
manifest() { printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"%s"\n}\n' "$2" "$3" "$4" >"$1/appmanifest_$2.acf"; }
[[ $(run) == null ]] || fail "no Steam: $(run)"
flat=$t/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps
mkdir -p "$flat"
manifest "$flat" 7 "Flathub Game" 4
[[ $(run) == '["Flathub Game"]' ]] || fail "Flathub's Steam: $(run)"
# Its library list names its own folder as the sandbox sees it (~/.local/share/Steam), not there outside it
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$t/.local/share/Steam" >"$flat/libraryfolders.vdf"
[[ $(run) == '["Flathub Game"]' ]] || fail "Flathub's Steam with its library list: $(run)"
steam=$t/.local/share/Steam/steamapps other=$t/drive/steamapps
mkdir -p "$steam" "$other"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' \
    "$t/.local/share/Steam" "$t/drive" >"$steam/libraryfolders.vdf"
manifest "$steam" 1 "Half-Life" 4
manifest "$steam" 2 "Proton 9.0" 4
manifest "$steam" 3 "Updating" 1030
manifest "$other" 4 'The \"Quoted\" Game' 6
manifest "$other" 5 "Steam Linux Runtime 3.0 (sniper)" 4
want='["Half-Life", "The \"Quoted\" Game", "Updating"]'
# (1030: an installed game downloading an update, still installed; 1 alone: not yet)
manifest "$steam" 6 "Not Yet" 1
[[ $(run) == "$want" ]] || fail "got $(run), want $want"
echo "ok steam-installed-games"
