#!/usr/bin/env bash
# The Super+Tab switcher's ×: which workspace a cleaned one's windows join (dots.merge_target: the nearest with
# windows, the previous on a tie, none without one), and dots.clean_workspace moving them there on each screen's own
# workspace of that column (minimised ones to its minimised workspace), silently
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip workspace-merge (no lua)"; exit 0; }
cat >"$t/test.lua" <<'L'
-- Hyprland's hl, as little as loading the file needs: anything not given here does nothing
local moves = {}
local screens = { { name = "A", x = 0, y = 0 }, { name = "B", x = 1920, y = 0 } }
local windows = {}
hl = setmetatable({
    get_monitors = function() return screens end,
    get_windows = function() return windows end,
    dispatch = function(d) moves[#moves + 1] = d end,
    dsp = { window = { move = function(a) return a end } },
}, { __index = function() return function() end end })
dots = {}
dofile(arg[1])
local t = dots.merge_target
local function set(...) local s = {}; for _, n in ipairs({ ... }) do s[n] = true end; return s end
assert(t(3, set(2, 3, 4)) == 2, "the previous didn't win a tie")
assert(t(3, set(1, 3, 4)) == 4, "the nearer next didn't beat the farther previous")
assert(t(5, set(1, 5, 9)) == 1, "a tie across a gap in the numbers didn't go to the previous")
assert(t(5, set(2, 5, 7)) == 7, "across gaps: not the nearer")
assert(t(1, set(1, 4)) == 4, "the 1st: not the next with windows")
assert(t(3, set(3)) == nil, "a target with no other workspace's windows")
assert(t(3, set()) == nil, "a target with none at all")
-- Two screens: column 3 (3 and 13, a minimised one on 13) joins column 2; the widgets (pinned) and special ones stay
windows = {
    { address = "a", workspace = { id = 3 } },
    { address = "b", workspace = { id = -99, name = "special:minimised-13" } },
    { address = "c", workspace = { id = 12 } },
    { address = "d", workspace = { id = 3 }, pinned = true }, -- (on the cleaned column: moved but for the pinned check)
    { address = "e", workspace = { id = -98, name = "special:hidden" } },
    { address = "f", workspace = { id = 6 } },
}
dots.clean_workspace(3)
local got = {}
for _, m in ipairs(moves) do got[#got + 1] = m.window.address .. ">" .. m.workspace .. (m.follow == false and "" or "!") end
assert(table.concat(got, ",") == "a>2,b>special:minimised-12", "moved: " .. table.concat(got, ","))
-- Nothing else with windows: nothing moves
moves, windows = {}, { { address = "a", workspace = { id = 3 } } }
dots.clean_workspace(3)
assert(#moves == 0, "moved with nowhere to go")
-- One screen: workspace numbers as they are (11 is a workspace of its own, not the 1st's column)
moves, screens = {}, { screens[1] }
windows = { { address = "a", workspace = { id = 11 } }, { address = "c", workspace = { id = 2 } }, { address = "f", workspace = { id = 13 } } }
dots.clean_workspace(11)
assert(#moves == 1 and moves[1].workspace == 13, "one screen: not the nearest by number")
-- The main screen set in the Settings app numbered first (1-10), whatever its place: B, right of A, gets 1
local rules = {}
hl.workspace_rule = function(r) rules[r.workspace] = r.monitor end
screens = { { name = "A", x = 0, y = 0 }, { name = "B", x = 1920, y = -500, description = "Sam B" } }
dots = { setting = function(k) return k == "screens.main" and "Sam B" or nil end }
dofile(arg[1])
assert(rules["1"] == "B" and rules["11"] == "A", "the main screen not 1-10: 1 on " .. tostring(rules["1"]))
L
out=$(HOME=$t XDG_RUNTIME_DIR=$t lua "$t/test.lua" "$here/.config/caelestia/user/workspaces.lua" 2>&1) || fail "$out"
echo "ok workspace-merge"
