#!/usr/bin/env bash
# desktop.lua: a screen that connects while the others sleep (the MSI, which disconnects asleep) sleeps with them, not
# lit alone; one that connects with them awake stays on. A screen gone: the pointer moved where it is (the lock
# screen's keyboard handed on, as only a pointer move does)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip screens-sleep (no lua)"; exit 0; }
run() { cd "$here" && lua -e '
local on, mons = {}, {}
hl = { on = function(e, f) on[e] = on[e] or {}; table.insert(on[e], f) end, exec_cmd = function() end,
       layer_rule = function() end, timer = function(f) f() end,
       get_monitors = function() return mons end, get_cursor_pos = function() return { x = 5, y = 7 } end,
       dispatch = function(d) io.write(d, "\n") end,
       dsp = { dpms = function(a) return "dpms " .. a.action .. " " .. a.monitor end,
               cursor = { move = function(p) return "move " .. p.x .. " " .. p.y end } } }
dots = {}
dofile(".config/caelestia/user/desktop.lua")
local function fire(e, m) for _, f in ipairs(on[e] or {}) do f(m) end end
'"$1"; }
out=$(run 'mons = { { name = "HDMI-A-1", dpms_status = false }, { name = "DP-1", dpms_status = true } }
fire("monitor.added", { name = "DP-1" })')
[[ $out == "dpms off DP-1" ]] || fail "a screen back while the others sleep not put to sleep: $out"
out=$(run 'mons = { { name = "HDMI-A-1", dpms_status = true }, { name = "DP-1", dpms_status = true } }
fire("monitor.added", { name = "DP-1" })')
[[ -z $out ]] || fail "a screen back with the others awake put to sleep: $out"
out=$(run 'mons = { { name = "DP-1", dpms_status = true } }
fire("monitor.added", { name = "DP-1" })')
[[ -z $out ]] || fail "the only screen put to sleep as it connected: $out"
out=$(run 'fire("monitor.removed", { name = "DP-1" })')
[[ $out == "move 5 7" ]] || fail "a screen gone, the pointer not moved where it is: $out"
echo "ok screens-sleep"
