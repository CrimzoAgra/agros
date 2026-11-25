-- The pointer between screens as LittleBigMouse does it on Windows: it comes out on the next screen at the same height
-- on your desk, in millimetres (each screen's size from its EDID), whatever their resolutions, the screens standing as
-- the Screens page lines them up (tops, bottoms or middles together, or in between). Where that height isn't on the
-- other screen (past its end), the pointer stays on its own, held at the edge, not thrown onto the other's nearest
-- corner. A screen with no size in its EDID (a VM's, a projector): the edges matched end to end instead (top corner to
-- top corner, bottom to bottom). Out of a
-- fullscreen game too, its pointer pushed into the edge, the focus taken to the other screen with it (the game keeps
-- the pointer in its window while it has it); one it holds still for aiming doesn't move, and one it puts back in the
-- middle after each move (older games) jumps a quarter of the screen and more at once: left alone. Nothing with one
-- screen. Hyprland has no pointer-motion event: its position read every 8 ms here, in Hyprland itself (no IPC), nothing
-- done while it doesn't move
local crossing = {}

-- Each side a pointer can leave a screen by: p the axis it crosses along, q the one along the edge
local SIDES = {
    { p = "x", s = "w", q = "y", t = "h", dir = 1 },   -- right
    { p = "x", s = "w", q = "y", t = "h", dir = -1 },  -- left
    { p = "y", s = "h", q = "x", t = "w", dir = 1 },   -- down
    { p = "y", s = "h", q = "x", t = "w", dir = -1 },  -- up
}

local boxes = {}
-- The edge the pointer is held at (held, below): its screen, side and line; nil once it leaves it
local pinned

-- The screens as Hyprland lays them out: position, and size at their scale, turned for a rotated one; mw, mh its size
-- in millimetres (0: unknown)
function crossing.set_boxes(list) boxes, pinned = list, nil end
local function read_boxes()
    local list = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.enabled ~= false and m.name ~= "FALLBACK" then
            local w, h = m.width / m.scale, m.height / m.scale
            local mw, mh = m.physical_width or 0, m.physical_height or 0
            if (m.transform or 0) % 2 == 1 then w, h, mw, mh = h, w, mh, mw end
            list[#list + 1] = { name = m.name, x = m.x, y = m.y, w = w, h = h, mw = mw, mh = mh }
        end
    end
    return list
end

local function near(a, b) return math.abs(a - b) <= 1 end
-- The line a side is on, for the screen left by it and for the one it leads to
local function leaving(b, k) return k.dir == 1 and b[k.p] + b[k.s] or b[k.p] end
local function entering(b, k) return k.dir == 1 and b[k.p] or b[k.p] + b[k.s] end
-- (monitors.lua's gap between screens, which Hyprland can't take the pointer across: this does)
local function gap() return dots.screen_gap or 0 end
-- A screen across the line, its edge on it or a gap past it
local function across(b, k, line)
    local d = (entering(b, k) - line) * k.dir
    return d >= -1 and d <= gap() + 1
end
local function box_at(p)
    for _, b in ipairs(boxes) do
        if p.x >= b.x and p.x < b.x + b.w and p.y >= b.y and p.y < b.y + b.h then return b end
    end
end

-- Where on b a pointer at q along a's edge comes out, by millimetres: b stood beside a as the layout lines them up (the
-- fraction of the way from tops together to bottoms together that their pixels are, the same in millimetres; equal
-- lengths in pixels: their offset, in a's millimetres). nil: a size unknown
local function by_size(a, b, q, k)
    local am, bm = a[k.q == "x" and "mw" or "mh"] or 0, b[k.q == "x" and "mw" or "mh"] or 0
    if am <= 0 or bm <= 0 then return nil end
    local a0, al, b0, bl = a[k.q], a[k.t], b[k.q], b[k.t]
    local off = math.abs(al - bl) > 1 and (b0 - a0) / (al - bl) * (am - bm) or (b0 - a0) * am / al
    return b0 + ((q - a0) * am / al - off) * bl / bm
end

-- Where a pointer at p, leaving screen a, lands across the line: on the screens there, by millimetres or (matched, or a
-- size unknown) each side's whole span along the line matched to the other's. nil: no screen on the far side, or that
-- place on none of them (past their ends: it doesn't go over)
-- shortcut: matched counts every screen with an edge on the line as one side, so two separate pairs on one line (far
-- apart) would share a span; fine for desks of two or three screens, split by overlap if that ever comes up
local function target(p, line, k, a)
    local flo, fhi, tlo, thi, to = math.huge, -math.huge, math.huge, -math.huge, {}
    for _, b in ipairs(boxes) do
        if near(leaving(b, k), line) then flo, fhi = math.min(flo, b[k.q]), math.max(fhi, b[k.q] + b[k.t]) end
        if across(b, k, line) then
            to[#to + 1] = b
            tlo, thi = math.min(tlo, b[k.q]), math.max(thi, b[k.q] + b[k.t])
        end
    end
    if #to == 0 or fhi <= flo then return nil end
    local matched = tlo + (p[k.q] - flo) / (fhi - flo) * (thi - tlo)
    -- (onto the screen there it falls on, a pixel's rounding either side)
    local best, onto
    for _, b in ipairs(to) do
        local v = by_size(a, b, p[k.q], k) or matched
        if v >= b[k.q] - 1 and v <= b[k.q] + b[k.t] then
            best, onto = math.max(b[k.q], math.min(b[k.q] + b[k.t] - 1, v)), b
            break
        end
    end
    if not onto then return nil, to end
    local out = { x = p.x, y = p.y }
    out[k.q] = best
    -- (going left or up, 2 px back from its far edge, as held: Hyprland never takes the pointer past 2558.999... on a
    -- 2560-wide screen, so put on 2559 a push back into the edge never moved it on, and it couldn't cross back until it
    -- left the edge)
    out[k.p] = entering(onto, k) + (k.dir == 1 and 1 or -2)
    return out, to
end

-- Held at an edge: a pixel back from it (Hyprland stops a pushed pointer on the edge and it doesn't move there, so a push
-- on into it was never seen), and pinned there: slid along it (no push needed: it's against the edge already) to where
-- the other screen lines up, it goes over
local function held(p, line, k, q, was)
    local back = { x = p.x, y = p.y }
    back[k.p] = k.dir == 1 and line - 2 or line + 1
    back[k.q] = q
    pinned = { box = was, k = k, line = line }
    return back
end

-- One reading of the pointer: where to move it (nil: leave it). last: the reading before
function crossing.step(p, last)
    local was, now = box_at(last), box_at(p)
    if not was or not now then return nil end
    if pinned and (now ~= pinned.box or math.abs(p[pinned.k.p] - pinned.line) > 2) then pinned = nil end
    for _, k in ipairs(SIDES) do
        local line = leaving(was, k)
        if now ~= was then
            -- It crossed where the edges meet: same distance across (Hyprland's), the matched place along it
            if across(now, k, line) and math.abs(p[k.p] - line) < 64 + gap() and math.abs(last[k.p] - line) < 64 then
                local out = target(last, line, k, was)
                if out then
                    out[k.p] = p[k.p]
                    return out
                end
                -- (that height not on it: back on this screen, at its edge, where it was along it)
                return held(p, line, k, math.max(was[k.q], math.min(was[k.q] + was[k.t] - 1, last[k.q])), was)
            end
        elseif math.abs(p[k.p] - line) <= 2 and ((p[k.p] - last[k.p]) * k.dir > 0 or pinned and pinned.k == k) then
            -- Pushed into its edge where nothing's right beyond, a screen further along: over to it (Hyprland stops it
            -- a hair short of the last pixel: 2558.999... on a 2560-wide screen)
            local out, to = target(p, line, k, was)
            for _, b in ipairs(to or {}) do
                -- (Hyprland crosses where their edges meet with no gap)
                if near(entering(b, k), line) and p[k.q] >= b[k.q] and p[k.q] < b[k.q] + b[k.t] then return nil end
            end
            -- (a screen across, but not at this height: held)
            if not out and to then return held(p, line, k, p[k.q], was) end
            pinned = nil
            return out
        end
    end
end

if not hl.timer or dots.verifying then return crossing end  -- (the config check, the tests: no timer)

local timer, last
local function tick()
    local p = hl.get_cursor_pos()
    if not p or last and p.x == last.x and p.y == last.y then return end
    local out = last and crossing.step(p, last)
    -- (how far it went since the last reading, against a quarter of its screen: a flick goes 70 px and more in 8 ms, a
    -- game putting it back in the middle half the screen)
    local was = last and box_at(last)
    local jump = was and (math.abs(p.x - last.x) + math.abs(p.y - last.y)) / (math.min(was.w, was.h) / 4) or 0
    last = { x = p.x, y = p.y }
    if not out then return end
    local w = hl.get_active_window()
    if w and w.fullscreen and w.fullscreen ~= 0 then
        if jump > 1 then return end
        -- (a game keeps the pointer inside its window while it has the focus, and Hyprland put it straight back: the
        -- focus to the other screen first)
        local to = box_at(out)
        if to and to.name then hl.dispatch(hl.dsp.focus({ monitor = to.name })) end
    end
    hl.dispatch(hl.dsp.cursor.move({ x = out.x, y = out.y }))
    last = out
end
local function refresh()
    boxes, last = read_boxes(), nil
    if #boxes > 1 and not timer then
        timer = hl.timer(tick, { timeout = 8, type = "repeat" })
    end
    if timer then timer:set_enabled(#boxes > 1) end
end
refresh()
for _, e in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed" }) do hl.on(e, refresh) end
return crossing
