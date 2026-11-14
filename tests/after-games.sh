#!/usr/bin/env bash
# after-games waits while a game is open (game-focus --game-open), not for a store launcher's window (tagged like a game
# under Proton), and returns at once outside Hyprland
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir "$t/bin"
# hyprctl lists $t/clients (none: Hyprland not running), only told which Hyprland (-i) as from an SSH login; each sleep
# is a minute waited, after which the game closes
printf '#!/bin/sh\n[ "$1" = -i ] || exit 1\ncat %s/clients 2>/dev/null || exit 1\n' "$t" >"$t/bin/hyprctl"
printf '#!/bin/sh\necho >>%s/waited\necho "[]" >%s/clients\n' "$t" "$t" >"$t/bin/sleep"
chmod +x "$t/bin/"*
waits() { rm -f "$t/waited"; HYPRLAND_INSTANCE_SIGNATURE='' PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/after-games" || fail "didn't return"; if [[ -e $t/waited ]]; then wc -l <"$t/waited"; else echo 0; fi; }
[[ $(waits) == 0 ]] || fail "waited outside Hyprland"
# (a store launcher by its program, as game-focus knows one: a process of its own, EA's under Wine)
(exec -a 'C:\EA\EADesktop.exe' sleep 30) & ea=$!
# ...and Rockstar's, by its folder (its program is only Launcher.exe), with Proton's class
(exec -a 'C:\Program Files\Rockstar Games\Launcher\Launcher.exe' sleep 30) & rockstar=$!
trap 'kill $ea $rockstar 2>/dev/null; rm -rf "$t"' EXIT
echo "[{\"title\": \"EA\", \"tags\": [\"game*\"], \"pid\": $ea}, {\"title\": \"foot\", \"tags\": []}]" >"$t/clients"
[[ $(waits) == 0 ]] || fail "waited for a store launcher"
echo "[{\"title\": \"Rockstar Games Launcher\", \"class\": \"steam_app_12210\", \"tags\": [\"game\"], \"pid\": $rockstar}]" >"$t/clients"
[[ $(waits) == 0 ]] || fail "waited for Rockstar's launcher"
echo '[{"title": "Some Game", "tags": ["game"]}]' >"$t/clients"
[[ $(waits) == 1 ]] || fail "didn't wait for the game"
echo '[{"title": "Proton Game", "tags": ["game*"]}]' >"$t/clients"
[[ $(waits) == 1 ]] || fail "didn't wait for a game tagged as under Proton"
# A Steam game by its class alone (Proton's steam_app_<id>, no tag yet)
echo '[{"title": "Proton Game", "class": "steam_app_1091500", "tags": []}]' >"$t/clients"
[[ $(waits) == 1 ]] || fail "didn't wait for a Steam game known by its class"
echo "ok after-games"
