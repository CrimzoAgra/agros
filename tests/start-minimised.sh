#!/usr/bin/env bash
# An app Startup starts minimised (AGROS_START_MINIMISED=1, user/apps.lua): its windows of its first minute minimised as
# they open, the minute counted from the start of the app the login started (the topmost process with the mark), not
# from the window's own process: a game Steam (started so) runs later inherits the mark and isn't minimised
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip start-minimised (no lua)"; exit 0; }
mkdir -p "$t/.local/bin" && cp "$here/.local/bin/store-launchers" "$t/.local/bin/"
out=$(cd "$here" && HOME=$t lua -e '
local any = setmetatable({}, { __index = function(s) return s end, __call = function() end })
local handlers = {}
hl = setmetatable({ on = function(_, f) handlers[#handlers + 1] = f end, window_rule = function() return any end }, { __index = function() return any end })
dots = { setting = function() return nil end, bind = function() return {} end, verifying = true }
-- Made-up processes in /proc: pid = { parent, started (s since boot), marked }; the clock at 1000 s since boot
local procs = {
    [9100] = { 1, 400, true },     -- Steam, started minimised at login 10 min ago
    [9101] = { 9100, 995, true },  -- a game it started 5 s ago
    [9200] = { 1, 990, true },     -- an app the login started 10 s ago
    [9201] = { 9200, 992, true },  -- its sandboxed program (a Flatpak), its window
    [9300] = { 1, 995, false },    -- an app started by hand
}
local real_open = io.open
io.open = function(path, ...)
    local text
    if path == "/proc/uptime" then text = "1000.00 4000.00\n" end
    local pid, file = path:match("^/proc/(%d+)/(%a+)$")
    local p = pid and procs[tonumber(pid)]
    if p and file == "stat" then
        text = pid .. " (a b) c) S " .. p[1] .. (" 0"):rep(17) .. " " .. math.tointeger(p[2] * 100) .. " 0 0\n"
    elseif p and file == "environ" then
        text = "HOME=/x\0" .. (p[3] and "AGROS_START_MINIMISED=1\0" or "") .. "LANG=C\0"
    elseif pid and tonumber(pid) >= 9000 then
        return nil
    end
    if not text then return real_open(path, ...) end
    return { read = function() return text end, close = function() end, lines = function() return text:gmatch("[^\n]+") end }
end
dofile(".config/caelestia/user/apps.lua")
local started = {}
hl.exec_cmd = function(c) started[#started + 1] = c end
hl.get_window = function() return nil end
local function open(address, pid)
    local w = { address = address, pid = pid, title = "x", initial_title = "x", class = "x", initial_class = "x", tags = {} }
    for _, f in ipairs(handlers) do pcall(f, w) end
end
open("0xgame", 9101); open("0xsteam", 9100); open("0xapp", 9201); open("0xmine", 9300)
local got = {}
for _, c in ipairs(started) do
    local a = c:match("minimise_launcher%(%[%[(.-)%]%]%)")
    if a then got[#got + 1] = a end
end
io.write(table.concat(got, " "))
')
[[ $out == 0xapp ]] || fail "windows minimised: '$out' (want only the app the login started minimised, in its first minute)"
echo "ok start-minimised"
