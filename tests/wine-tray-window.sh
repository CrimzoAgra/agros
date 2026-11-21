#!/usr/bin/env bash
# Wine's own tray window (user/apps.lua's dots.close_wine_tray): an untitled window of Wine's explorer.exe /desktop is
# closed as it opens (white and full-screen over a Wayland-mode game, when Lutris's ShowSystray=0 didn't hold); not one
# with a title (a virtual desktop's), nor explorer.exe without /desktop, nor another program's
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip wine-tray-window (no lua)"; exit 0; }
# (bash stays the process, its command line as Wine's: "sleep 30; true" isn't run in place of it)
(exec -a 'C:\windows\system32\explorer.exe' bash -c 'sleep 30; true' /desktop) & tray=$!
(exec -a 'C:\windows\system32\explorer.exe' bash -c 'sleep 30; true' /desktop=Default,1920x1080) & named=$!
(exec -a 'C:\windows\system32\explorer.exe' bash -c 'sleep 30; true') & plain=$!
(exec -a 'C:\Games\Game.exe' bash -c 'sleep 30; true' /desktop) & other=$!
on_exit 'kill $tray $named $plain $other'
sleep 0.3
out=$(cd "$here" && HOME=$t lua -e '
local any = setmetatable({}, { __index = function(s) return s end, __call = function() end })
local handlers = {}
hl = setmetatable({ on = function(_, f) handlers[#handlers + 1] = f end, window_rule = function() return any end }, { __index = function() return any end })
dots = { setting = function() return nil end, bind = function() return {} end, verifying = true }
dofile(".config/caelestia/user/apps.lua")
local windows, closed, started = {}, {}, {}
hl.get_window = function(a) return windows[a:gsub("^address:", "")] end
hl.dsp = { window = { close = function(o) return o.window.address end } }
hl.dispatch = function(a) closed[#closed + 1] = a end
hl.exec_cmd = function(c) started[#started + 1] = c end
local function open(address, pid, title)
    windows[address] = { address = address, pid = pid, title = title, tags = {} }
    for _, f in ipairs(handlers) do pcall(f, windows[address]) end
end
open("0xtray", '"$tray"', "")
open("0xnamed", '"$named"', "Default - Wine desktop")
open("0xlate", '"$named"', "")
open("0xplain", '"$plain"', "")
open("0xother", '"$other"', "")
-- (half a second on: the late one has its title by then)
windows["0xlate"].title = "Default - Wine desktop"
for _, c in ipairs(started) do
    local a = c:match("close_wine_tray%(%[%[(.-)%]%]%)")
    if a then dots.close_wine_tray(a) end
end
io.write(table.concat(closed, " "))
')
[[ $out == 0xtray* ]] || fail "Wine's tray window not closed: closed '$out'"
[[ $out == "0xtray 0xlate" ]] && fail "a window titled by the time it was looked at closed (a virtual desktop's)"
[[ $out == 0xtray ]] || fail "closed more than Wine's tray window: $out"
echo "ok wine-tray-window"
