#!/usr/bin/env bash
# A store launcher a game started (user/apps.lua): its window minimised as it opens, for any launcher in
# ~/.local/bin/store-launchers' list (Battle.net's too, which a list of its own left shown); not one you opened yourself
# (its Lutris name is the launcher's), nor another program's window
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip launcher-minimised (no lua)"; exit 0; }
mkdir -p "$t/.local/bin" && cp "$here/.local/bin/store-launchers" "$t/.local/bin/"
# (bash stays the process, its command line as Wine's)
(GAME_NAME=Overwatch exec -a 'C:\Program Files (x86)\Battle.net\Battle.net.exe' bash -c 'sleep 30; true') & bnet=$!
(GAME_NAME=Battle.net exec -a 'C:\Program Files (x86)\Battle.net\Battle.net.exe' bash -c 'sleep 30; true') & own=$!
(GAME_NAME=Overwatch exec -a 'C:\Games\Overwatch.exe' bash -c 'sleep 30; true') & game=$!
on_exit 'kill $bnet $own $game'
sleep 0.3
out=$(cd "$here" && HOME=$t lua -e '
local any = setmetatable({}, { __index = function(s) return s end, __call = function() end })
local handlers = {}
hl = setmetatable({ on = function(_, f) handlers[#handlers + 1] = f end, window_rule = function() return any end }, { __index = function() return any end })
dots = { setting = function() return nil end, bind = function() return {} end, verifying = true }
dofile(".config/caelestia/user/apps.lua")
local started = {}
hl.exec_cmd = function(c) started[#started + 1] = c end
hl.get_window = function() return nil end
local function open(address, pid)
    local w = { address = address, pid = pid, title = "x", initial_title = "x", initial_class = "steam_app_default", tags = {} }
    for _, f in ipairs(handlers) do pcall(f, w) end
end
open("0xbnet", '"$bnet"'); open("0xown", '"$own"'); open("0xgame", '"$game"')
local got = {}
for _, c in ipairs(started) do
    local a = c:match("minimise_launcher%(%[%[(.-)%]%]%)")
    if a then got[#got + 1] = a end
end
io.write(table.concat(got, " "))
')
[[ $out == 0xbnet ]] || fail "launchers minimised: '$out' (want only Battle.net started by a game)"
echo "ok launcher-minimised"
