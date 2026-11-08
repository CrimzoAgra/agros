#!/usr/bin/env bash
# dots.is_game (user/apps.lua), what windows.lua and titlebars.lua leave alone: Caelestia's "game" tag (Proton, Lutris,
# gamescope) and a native Steam game not tagged yet (SteamGameId + Steam's games folder); not other windows
set -euo pipefail
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip is-game (no lua)"; exit 0; }
sleep 30 & game=$!
# A stand-in native game: SteamGameId set, run from a path with steamapps/common in it
mkdir -p "$t/steamapps/common/Game"; cp /usr/bin/sleep "$t/steamapps/common/Game/game"
SteamGameId=123 "$t/steamapps/common/Game/game" 30 & native=$!
# ...and one started as ./game from its folder (the path only in its file, not its command line)
(cd "$t/steamapps/common/Game" && SteamGameId=124 exec ./game 30) & relative=$!
# Store launchers: one a Lutris game started (GAME_NAME the game's), one a Steam game started, one opened from its own
# Lutris entry (GAME_NAME the launcher's), one opened some other way (neither)
GAME_NAME="Battlefield 1" sleep 30 & forlutris=$!
SteamGameId=1238840 sleep 30 & forsteam=$!
GAME_NAME="EA App" sleep 30 & byentry=$!
GAME_NAME="Assassin's Creed Origins" sleep 30 & origins=$!
env -u GAME_NAME -u SteamGameId sleep 30 & byhand=$!
# A program whose name has ") " in it (the start time in /proc/<pid>/stat is after the last ")")
cp /usr/bin/sleep "$t/a) b"; "$t/a) b" 30 & odd=$!
trap 'kill $game $native $relative $forlutris $forsteam $byentry $byhand $origins $odd 2>/dev/null; rm -rf "$t"' EXIT
for _ in $(seq 50); do [[ $(cat "/proc/$odd/comm") == "a) b" && $(cat "/proc/$relative/comm") == game ]] && break; sleep 0.05; done
start=$(sed 's/.*) //' "/proc/$odd/stat" | cut -d' ' -f20)
out=$(cd "$here" && lua -e '
local any = setmetatable({}, { __index = function(s) return s end, __call = function() end })
local handlers = {}
hl = setmetatable({ on = function(_, f) handlers[#handlers + 1] = f end, window_rule = function() return any end }, { __index = function() return any end })
dots = { setting = function() return nil end, bind = function() return {} end }
dofile(".config/caelestia/user/apps.lua")
local function say(name, w) io.write(name, "=", tostring(dots.is_game(w)), "\n") end
say("tagged", { tags = { "game" }, pid = -1 })
say("tagged_star", { tags = { "game*" }, pid = -1 })
say("plain", { tags = { "maximised" }, pid = '"$game"' })
say("native", { tags = {}, pid = '"$native"' })
say("relative", { tags = {}, pid = '"$relative"' })
say("notsteam", { tags = {}, pid = '"$forsteam"' })  -- SteamGameId, not from Steam'"'"'s games folder
local function up(f, name)
    for i = 1, 99 do local n, v = debug.getupvalue(f, i); if n == name then return v, i end end
end
-- Each process looked at once (by its pid and start time), whatever its name
local steam_game_id = up(dots.is_game, "steam_game_id")
local read_game_id, i = up(steam_game_id, "read_game_id")
local reads = 0
debug.setupvalue(steam_game_id, i, function(pid) reads = reads + 1; return read_game_id(pid) end)
dots.is_game({ tags = {}, pid = '"$odd"' }); dots.is_game({ tags = {}, pid = '"$odd"' })
io.write("reads=", reads, "\n")
io.write("cached=", tostring(up(steam_game_id, "game_ids")["'"$odd:$start"'"] == false), "\n")
-- A launcher'"'"'s age (by its start time) right whatever its name too
local process_age
for _, f in ipairs(handlers) do process_age = process_age or up(f, "process_age") end
local odd, plain = process_age('"$odd"'), process_age('"$game"')
io.write("age=", tostring(odd and plain and math.abs(odd - plain) < 5), "\n")
for _, c in ipairs({ { "forlutris", '"$forlutris"' }, { "forsteam", '"$forsteam"' }, { "byentry", '"$byentry"' },
                     { "byhand", '"$byhand"' }, { "origins", '"$origins"' } }) do
    io.write(c[1], "=", tostring(dots.started_for_game(c[2])), "\n")
end')
for want in tagged=true tagged_star=true plain=false native=true relative=true forlutris=true forsteam=true byentry=false byhand=false origins=true notsteam=false reads=1 cached=true \
    age=true; do
    grep -qx "$want" <<<"$out" || { echo "FAIL: is_game: wanted $want, got: $(tr '\n' ' ' <<<"$out")"; exit 1; }
done
echo "ok is-game"
