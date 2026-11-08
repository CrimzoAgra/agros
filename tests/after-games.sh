#!/usr/bin/env bash
# after-games waits while a game is open, not for a store launcher's window (tagged like a game under Proton), and
# returns at once outside Hyprland
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir "$t/bin"
# hyprctl lists $t/clients (none: Hyprland not running), only told which Hyprland (-i) as from an SSH login; each sleep
# is a minute waited, after which the game closes
printf '#!/bin/sh\n[ "$1" = -i ] || exit 1\ncat %s/clients 2>/dev/null || exit 1\n' "$t" >"$t/bin/hyprctl"
printf '#!/bin/sh\necho >>%s/waited\necho "[]" >%s/clients\n' "$t" "$t" >"$t/bin/sleep"
chmod +x "$t/bin/"*
waits() { rm -f "$t/waited"; HYPRLAND_INSTANCE_SIGNATURE= PATH=$t/bin:$PATH timeout 10 "$here/.local/bin/after-games" || fail "didn't return"; wc -l <"$t/waited" 2>/dev/null || echo 0; }
[[ $(waits) == 0 ]] || fail "waited outside Hyprland"
echo '[{"title": "EA", "tags": ["game*"]}, {"title": "foot", "tags": []}]' >"$t/clients"
[[ $(waits) == 0 ]] || fail "waited for a store launcher"
echo '[{"title": "Some Game", "tags": ["game"]}]' >"$t/clients"
[[ $(waits) == 1 ]] || fail "didn't wait for the game"
echo '[{"title": "Proton Game", "tags": ["game*"]}]' >"$t/clients"
[[ $(waits) == 1 ]] || fail "didn't wait for a game tagged as under Proton"
echo "ok after-games"
