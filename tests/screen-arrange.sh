#!/usr/bin/env bash
# Screens: the pointer between two screens of different heights (crossing.lua, LittleBigMouse's way): the edge matched
# end to end both ways, the taller one's corner past the shorter one's edge leading over too, Hyprland's own crossing
# and a pointer sliding along an edge or warped across left alone; and the Settings app's drag (shell.qml's
# arrangeSnap, arrangeNormal): a screen let go snaps to a side of the other, lined up, never over it, the top left at 0,0
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
if command -v lua >/dev/null; then
    out=$(cd "$here" && lua -e '
hl, dots = {}, { setting = function() end }
local c = dofile(".config/caelestia/user/crossing.lua")
-- a 2560x1440 at 0,0, a 1920x1080 to its right, tops lined up
c.set_boxes({ { x = 0, y = 0, w = 2560, h = 1440 }, { x = 2560, y = 0, w = 1920, h = 1080 } })
local function say(p) io.write(p and string.format("%.0f,%.0f", p.x, p.y) or "-", "\n") end
say(c.step({ x = 2561, y = 540 }, { x = 2559, y = 540 }))     -- crossed right at 540: 3/8 down the edge
say(c.step({ x = 2558.9999, y = 1300 }, { x = 2400, y = 1300 })) -- pushed into the corner below the small one (where Hyprland stops it)
say(c.step({ x = 2558, y = 1000 }, { x = 2561, y = 1000 }))   -- crossed left at 1000
say(c.step({ x = 2559, y = 500 }, { x = 2558, y = 500 }))     -- at the edge where Hyprland crosses itself
say(c.step({ x = 2559, y = 1300 }, { x = 2559, y = 1250 }))   -- sliding down the edge
say(c.step({ x = 3520, y = 540 }, { x = 1280, y = 720 }))     -- warped to the other screen (a key)
say(c.step({ x = 0, y = 700 }, { x = 1, y = 700 }))           -- the left edge, nothing beyond
')
    want=$'2561,405\n2561,975\n2558,1333\n-\n-\n-\n-'
    [[ $out == "$want" ]] || fail "the pointer between screens: got"$'\n'"$out"$'\n'"want"$'\n'"$want"
    # By real size: a 27" 2560x1440 (600x330 mm) beside a 24" 1080p one standing on its side (290x520 mm): the pointer
    # at the same height in millimetres, tops lined up, then bottoms; past the shorter one's end onto its corner; and
    # the edges matched end to end when asked to
    out=$(cd "$here" && lua -e '
hl, dots = {}, { setting = function() end }
local c = dofile(".config/caelestia/user/crossing.lua")
local function say(p) io.write(p and string.format("%.0f,%.0f", p.x, p.y) or "-", "\n") end
c.set_boxes({ { x = 0, y = 0, w = 2560, h = 1440, mw = 600, mh = 330 }, { x = 2560, y = 0, w = 1080, h = 1920, mw = 290, mh = 520 } })
say(c.step({ x = 2561, y = 720 }, { x = 2559, y = 720 }))         -- 165 mm down: 609 px down the tall one
say(c.step({ x = 2560.5, y = 1500 }, { x = 2562, y = 1500 }))     -- 406 mm down, below the short one: its corner
c.set_boxes({ { x = 0, y = 480, w = 2560, h = 1440, mw = 600, mh = 330 }, { x = 2560, y = 0, w = 1080, h = 1920, mw = 290, mh = 520 } })
say(c.step({ x = 2561, y = 1200 }, { x = 2559, y = 1200 }))       -- bottoms lined up: 355 mm down the tall one
say(c.step({ x = 2558, y = 1311 }, { x = 2561, y = 1311 }))       -- and back
c.mode = "matched"
say(c.step({ x = 2561, y = 1200 }, { x = 2559, y = 1200 }))       -- matched: halfway down to halfway down
')
    want=$'2561,609\n2559,1439\n2561,1311\n2558,1200\n2561,960'
    [[ $out == "$want" ]] || fail "the pointer between screens by real size: got"$'\n'"$out"$'\n'"want"$'\n'"$want"
else
    skipped "no lua: the pointer's crossing not checked"
fi
if command -v node >/dev/null; then
    qml=$here/.config/quickshell/settings/shell.qml
    fns=$(for f in arrangeSnap arrangeNormal; do sed -n "/^    function $f(/,/^    }$/p" "$qml"; done |
        sed -E '/^    function /{s/: (var|int|real)([,)])/\2/g; s/\): var \{$/) {/}')
    [[ -n $fns ]] || fail "the Settings app's screen snapping not found"
    out=$(node -e "$fns
const big = { x: 0, y: 0, w: 2560, h: 1440 }, small = { x: 2560, y: 0, w: 1920, h: 1080 };
const show = p => p.x + ',' + p.y;
console.log(show(arrangeSnap([big, small], 1, 2600, 30)));    // near its right side: lined up with the top
console.log(show(arrangeSnap([big, small], 1, -1900, 200)));  // to the left
console.log(show(arrangeSnap([big, small], 1, 300, 1400)));   // below
console.log(show(arrangeSnap([big, small], 1, 1000, 500)));   // dropped on top of it: out by the nearest side (below)
console.log(show(arrangeSnap([big, small], 1, 2560, 1300)));  // too low to touch: up to share a quarter
console.log(arrangeNormal([big, { ...small, x: -1920, y: 180 }]).map(show).join(' '));")
    want=$'2560,0\n-1920,180\n320,1440\n1000,1440\n2560,1170\n1920,0 0,180'
    [[ $out == "$want" ]] || fail "the Settings app's screen snapping: got"$'\n'"$out"$'\n'"want"$'\n'"$want"
else
    skipped "no node: the Settings app's screen snapping not checked"
fi
echo "ok screen-arrange"
