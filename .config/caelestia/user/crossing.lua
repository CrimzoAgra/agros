-- The pointer between screens as LittleBigMouse does it on Windows: an edge two screens share is matched end to end, so
-- the whole edge of a taller screen leads to the shorter one beside it (no dead corner where the pointer stops at the
-- edge), and the pointer comes out the same fraction of the way along it (top corner to top corner, bottom to bottom),
-- not at the same pixel row. Settings app: Screens, "Moving between screens" (screens.crossing; "off": Hyprland's own,
-- the pointer crosses only where the two edges meet, at the same row). Nothing with one screen, nor while a fullscreen
-- window has focus (a game's aim). Hyprland has no pointer-motion event: its position read every 8 ms here, in
-- Hyprland itself (no IPC), nothing done while it doesn't move
local crossing = {}

-- Each side a pointer can leave a screen by: p the axis it crosses along, q the one along the edge
local SIDES = {
    { p = "x", s = "w", q = "y", t = "h", dir = 1 },   -- right
    { p = "x", s = "w", q = "y", t = "h", dir = -1 },  -- left
    { p = "y", s = "h", q = "x", t = "w", dir = 1 },   -- down
    { p = "y", s = "h", q = "x", t = "w", dir = -1 },  -- up
}

local boxes = {}

-- The screens as Hyprland lays them out: position, and size at their scale, turned for a rotated one
function crossing.set_boxes(list) boxes = list end
local function read_boxes()
    local list = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.enabled ~= false and m.name ~= "FALLBACK" then
            local w, h = m.width / m.scale, m.height / m.scale
            if (m.transform or 0) % 2 == 1 then w, h = h, w end
            list[#list + 1] = { x = m.x, y = m.y, w = w, h = h }
        end
    end
    return list
end

local function near(a, b) return math.abs(a - b) <= 1 end
-- The line a side is on, for the screen left by it and for the one it leads to
local function leaving(b, k) return k.dir == 1 and b[k.p] + b[k.s] or b[k.p] end
local function entering(b, k) return k.dir == 1 and b[k.p] or b[k.p] + b[k.s] end
local function box_at(p)
    for _, b in ipairs(boxes) do
        if p.x >= b.x and p.x < b.x + b.w and p.y >= b.y and p.y < b.y + b.h then return b end
    end
end

-- Where a pointer at p crossing the line lands: the screens on each side of the line, each side's whole span along it
-- matched to the other's. nil: no screen on the far side
-- shortcut: every screen with an edge on the line counts as one side, so two separate pairs on one line (far apart)
-- would share a span; fine for desks of two or three screens, split by overlap if that ever comes up
local function target(p, line, k)
    local flo, fhi, tlo, thi, to = math.huge, -math.huge, math.huge, -math.huge, {}
    for _, b in ipairs(boxes) do
        if near(leaving(b, k), line) then flo, fhi = math.min(flo, b[k.q]), math.max(fhi, b[k.q] + b[k.t]) end
        if near(entering(b, k), line) then
            to[#to + 1] = b
            tlo, thi = math.min(tlo, b[k.q]), math.max(thi, b[k.q] + b[k.t])
        end
    end
    if #to == 0 or fhi <= flo then return nil end
    local v = tlo + (p[k.q] - flo) / (fhi - flo) * (thi - tlo)
    -- (a gap along the line between two screens there: onto the closer one)
    local best, gap
    for _, b in ipairs(to) do
        local c = math.max(b[k.q], math.min(b[k.q] + b[k.t] - 1, v))
        if not gap or math.abs(c - v) < gap then best, gap = c, math.abs(c - v) end
    end
    local out = { x = p.x, y = p.y }
    out[k.q] = best
    out[k.p] = line + (k.dir == 1 and 1 or -1)
    return out, to
end

-- One reading of the pointer: where to move it (nil: leave it). last: the reading before
function crossing.step(p, last)
    local was, now = box_at(last), box_at(p)
    if not was or not now then return nil end
    for _, k in ipairs(SIDES) do
        local line = leaving(was, k)
        if now ~= was then
            -- It crossed where the edges meet: same distance across (Hyprland's), the matched place along it
            if near(entering(now, k), line) and math.abs(p[k.p] - line) < 64 and math.abs(last[k.p] - line) < 64 then
                local out = target(last, line, k)
                if out then out[k.p] = p[k.p] end
                return out
            end
        elseif (p[k.p] - last[k.p]) * k.dir > 0 and math.abs(p[k.p] - line) < 2 then
            -- Pushed into its edge where nothing's right beyond, a screen further along: over to it (Hyprland stops it
            -- a hair short of the last pixel: 2558.999... on a 2560-wide screen)
            local out, to = target(p, line, k)
            for _, b in ipairs(to or {}) do
                if p[k.q] >= b[k.q] and p[k.q] < b[k.q] + b[k.t] then return nil end  -- (Hyprland crosses here)
            end
            return out
        end
    end
end

if not hl.timer or dots.verifying then return crossing end  -- (the config check, the tests: no timer)
if dots.setting("screens.crossing") == "off" then return crossing end

local timer, last
local function tick()
    local p = hl.get_cursor_pos()
    if not p or last and p.x == last.x and p.y == last.y then return end
    local out = last and crossing.step(p, last)
    last = { x = p.x, y = p.y }
    if not out then return end
    local w = hl.get_active_window()
    if w and w.fullscreen and w.fullscreen ~= 0 then return end
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
