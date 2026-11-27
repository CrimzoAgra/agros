-- Screens: layout, refresh rates and colours.
-- Rules for one machine's own screens live in user/hosts/<hostname>.lua; any other screen gets its own resolution at
-- its fastest refresh rate.

-- A rule's "desc:<make and model>" (no serial number in the repo) names the connected screen whose description starts
-- with it: its full description, serial included. Screens come and go with a config reload (workspaces.lua), so this
-- runs again then
local taken, named = {}, {}
function dots.monitor(rule)
    local prefix = (rule.output or ""):match("^desc:(.+)$")
    -- (all: a screen that's off too, so its rule is there when it's turned on)
    for _, m in ipairs(prefix and hl.get_monitors({ all = true }) or {}) do
        -- (two screens of one model: each rule gets the next one)
        if (m.description or ""):sub(1, #prefix) == prefix and not taken[m.description] then
            taken[m.description] = true
            rule.output = "desc:" .. m.description
            break
        end
    end
    named[rule.output or ""] = rule  -- (its fields: the lid's rule for a panel starts from them)
    hl.monitor(rule)
end

-- Any other monitor: to the right of the others. Never above or left ("auto-center-up" over a laptop panel): that's
-- negative coordinates, and Proton (Wine) games under XWayland then aim the mouse somewhere else than the pointer.
-- Set before the host file (a screen's own rule wins over this one whatever the order), so a mistake in that file (it
-- stops the rest of this one) still leaves every screen on
dots.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- A VM's screen (Virtual-1...): 1, as it has no physical size for "auto" to go by (it took 2 in VMware). Its size the
-- kernel's preferred mode, not Hyprland's "preferred": Hyprland reads a screen's modes once, when it connects, so after
-- the VM's window was resized it kept the old size (vm-screen-follow reloads when the kernel's changes)
for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
    if m.name:match("^Virtual%-%d+$") then
        -- (SYSFS: another /sys, for tests/monitor-desc.sh)
        local p = io.popen("head -qn1 " .. (os.getenv("SYSFS") or "/sys") .. "/class/drm/card*-" .. m.name .. "/modes 2>/dev/null")
        local mode = p and p:read("l")
        if p then p:close() end
        dots.monitor({ output = m.name, mode = mode or "preferred", position = "auto", scale = 1 })
    end
end

-- This machine's own screens (user/hosts/<hostname>.lua), if it has a file. Not under pcall: a mistake in it shows as
-- a config error
local f = io.open("/proc/sys/kernel/hostname")
local host = f and f:read("l") or ""
if f then f:close() end
local host_file = os.getenv("HOME") .. "/.config/caelestia/user/hosts/" .. host .. ".lua"
local exists = host ~= "" and io.open(host_file)
if exists then
    exists:close()
    -- require when it can: Hyprland watches files loaded that way, so saving it reloads like the other user/ files. Not
    -- for a hostname with a dot (terra.lan), which require would read as a folder
    if host:find(".", 1, true) then dofile(host_file) else require("user.hosts." .. host) end
end

-- Any other screen connected: its own resolution (its preferred mode's) at the fastest refresh rate it has there, as the
-- kernel console and the login screen take it (screenmode.py). "preferred" keeps that mode's own rate, 60 on many
-- 144 Hz screens, and the screen would resync at login. A rule of its own by name (screens plugged in later get theirs
-- with the config reload workspaces.lua does); after the host file, so its screens keep their rules. Only when there is
-- a faster one: else "preferred" stays, which a VM's screen needs to follow its window (vm-screen-follow)
for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
    local preferred, best
    for _, md in ipairs(m.available_modes or {}) do
        if md.preferred then preferred = md; break end
    end
    if preferred and not named[m.name] and not named["desc:" .. (m.description or "")] then
        best = preferred
        for _, md in ipairs(m.available_modes) do
            -- (more than a rounding apart: 60.00 and 59.94 are one rate)
            if md.width == best.width and md.height == best.height and md.refresh_rate > best.refresh_rate + 0.5 then best = md end
        end
    end
    if best and best ~= preferred then
        named[m.name] = { mode = string.format("%dx%d@%.2f", best.width, best.height, best.refresh_rate),
                          position = "auto", scale = "auto" }
        hl.monitor({ output = m.name, mode = named[m.name].mode, position = "auto", scale = "auto" })
    end
end

-- Screens set in the Settings app (Screens page), by their full description (make, model and serial), or by their
-- connector's name for a screen with none (a VM's, with no EDID: Virtual-1), as the Settings app and workspaces.lua name
-- them: screens.<description>.mode ("1920x1080@143.98"), .scale ("1.5"), .position ("1920x0"), .transform ("1": turned
-- 90°), .enabled, .hdr ("on": always); each one left
-- empty keeps the rule above (the host file's, the fastest refresh rate). screens.main: that one at 0x0 (the first
-- screen: workspaces 1-10), the others to its right unless given a position (here, or by the host file). After the
-- rules above, so these win, and before the lid's, which starts from them
local mine, main = {}, dots.setting("screens.main") or ""
local function id(m) return (m.description or "") ~= "" and m.description or m.name end
-- (its rule's output: by description where it has one, so it follows the screen to another connector)
local function rule_output(m) return (m.description or "") ~= "" and "desc:" .. m.description or m.name end
for key, value in pairs(dots.settings("screens.")) do
    local desc, field = key:match("^screens%.(.+)%.(%a+)$")
    if desc then
        mine[desc] = mine[desc] or {}
        mine[desc][field] = value
    end
end

-- Laptop lid closed with another screen connected: the laptop's own panel (eDP, LVDS or DSI) off, as logind leaves it
-- on then (docked: it doesn't suspend), with workspaces on a dark panel and the pointer wandering onto it. Off by a rule
-- like the ones here: its windows go to the other screen's empty workspaces, and come back when the lid opens
-- (workspaces.lua, as for any screen unplugged). Closed with no other screen: left to logind (it suspends). output:
-- only to try it on a screen that isn't a panel
local function lid_closed()
    local p = io.popen("cat /proc/acpi/button/lid/*/state 2>/dev/null")
    local state = p and p:read("a") or ""
    if p then p:close() end
    return state:find("closed", 1, true) ~= nil
end
local function is_panel(m, output)
    if output then return m.name == output end
    return m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI")
end
-- Which screens are off, the one place that decides it, for the Settings app's rules and the lid's alike: the panels a
-- closed lid turns off (lid), and the screens the Settings app has off (set), never the last one left showing (a
-- panel under a closed lid isn't showing: docked, lid shut, the other screen turned off left both dark; the lid opened,
-- a panel turned off in the Settings app stays off)
local function screens_off(closed, output)
    local list, lid, set, others = {}, {}, {}, false
    for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
        if m.name ~= "FALLBACK" then  -- (Hyprland's stand-in with no screen at all)
            list[#list + 1] = m
            others = others or not is_panel(m, output)
        end
    end
    local left, wanted = {}, 0  -- (the screens the lid leaves; how many of them the Settings app has off)
    for _, m in ipairs(list) do
        if closed and others and is_panel(m, output) then
            lid[m.name] = true
        else
            left[#left + 1] = m
            if (mine[id(m)] or {}).enabled == false then wanted = wanted + 1 end
        end
    end
    -- Every one left set off: one stays on, the same one whatever order Hyprland lists them in: the main screen, else
    -- the laptop's panel, else the first by name
    local keep
    if wanted > 0 and wanted == #left then
        table.sort(left, function(a, b) return a.name < b.name end)
        for _, m in ipairs(left) do
            if main ~= "" and id(m) == main then keep = m; break end
            if not keep and is_panel(m) then keep = m end
        end
        keep = keep or left[1]
    end
    for _, m in ipairs(left) do
        if m ~= keep and (mine[id(m)] or {}).enabled == false then set[m.name] = true end
    end
    return lid, set
end

-- The pointer between screens (crossing.lua): a gap between them in Hyprland's layout, wider than the
-- pointer's picture, so Hyprland never takes the pointer across by itself at the same pixel row, drawing it there for a
-- frame before crossing.lua puts it at its height (it flickered), nor draws its picture on the next screen at that row
-- as it nears the edge: crossing.lua takes it over the gap, as LittleBigMouse does. Only when every screen showing has
-- its position from the Settings app (dragged into place there, where they're shown touching, as saved): each moved on
-- by one gap per screen edge before it, across and down
dots.screen_gap = 0
local gapped = {}
do
    local desk = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        local s = mine[id(m)] or {}
        local x, y = (type(s.position) == "string" and s.position or ""):match("^(%d+)x(%d+)$")
        if not x then desk = {}; break end
        -- (its size as this load sets it: a new mode, scale or rotation from the Settings app, else as it is)
        local w, h = (type(s.mode) == "string" and s.mode or ""):match("^(%d+)x(%d+)")
        w, h = tonumber(w) or m.width, tonumber(h) or m.height
        local sc, t = tonumber(s.scale) or m.scale or 1, tonumber(s.transform) or m.transform or 0
        w, h = w / sc, h / sc
        if t % 2 == 1 then w, h = h, w end
        desk[#desk + 1] = { name = m.name, x = tonumber(x), y = tonumber(y), w = w, h = h }
    end
    if #desk > 1 then
        dots.screen_gap = 64
        local function edges(d, p, s)  -- (the other screens' far edges at or before this one's start, each line once)
            local seen, n = {}, 0
            for _, o in ipairs(desk) do
                local e = math.floor(o[p] + o[s] + 0.5)
                if o ~= d and e <= d[p] and not seen[e] then seen[e], n = true, n + 1 end
            end
            return n
        end
        for _, d in ipairs(desk) do
            gapped[d.name] = string.format("%dx%d", d.x + 64 * edges(d, "x", "w"), d.y + 64 * edges(d, "y", "h"))
        end
    end
end

local off = {}  -- (the screens this load or the lid turned off: name to its rule's output (desc: or its name), or false)
local _, set_off = screens_off(lid_closed())
for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
    -- (no description: by its name, never a desc: rule with none, which would match every screen)
    local s = mine[id(m)] or {}
    local applied = named[rule_output(m)] or named[m.name] or {}
    -- (text, or not set: anything else, from a hand edit of settings.json, is left out; a mode the screen doesn't
    -- have, gone with a firmware or cable change, too: the rule that applied stays)
    local mode = type(s.mode) == "string" and s.mode ~= "" and s.mode or nil
    if mode then
        local found = false
        for _, md in ipairs(type(m.available_modes) == "table" and m.available_modes or {}) do
            found = found or string.format("%dx%d@%.2f", md.width, md.height, md.refresh_rate) == mode
        end
        mode = found and mode or nil
    end
    -- (the same for a position not in the Settings app's form, WxH, and a scale far outside its list: settings.lua has
    -- the screens' as saved in settings.json, a hand edit unchecked, and a rule Hyprland can't read is a config error
    -- here, before the lid's switch below)
    local position = type(s.position) == "string" and s.position:match("^%d+x%d+$") or nil
    local scale = tonumber(s.scale)
    scale = scale and scale >= 0.5 and scale <= 4 and scale or nil
    -- (rotation: 0 as it stands, 1 90°, 2 upside down, 3 270°, as Hyprland numbers them)
    local transform = tonumber(s.transform)
    transform = transform and transform >= 0 and transform <= 3 and math.floor(transform) == transform and transform or nil
    -- HDR always ("on": the Settings app offers it on a screen that takes it): 10-bit, the desktop's SDR colours shown
    -- in it. Else Hyprland's own: SDR, switched to HDR while a fullscreen game or video in HDR asks (render.cm_auto_hdr)
    local hdr = s.hdr == "on"
    -- A main screen: it at 0x0, the others where the host file puts them (not at 0x0: that's the main's now), else to
    -- its right
    local placed = applied.position ~= nil and applied.position ~= "auto" and applied.position ~= "0x0"
    if main ~= "" and not position and not (placed and id(m) ~= main) then
        position = id(m) == main and "0x0" or "auto-right"
    end
    if next(s) or position then
        -- (from the rule that applied to it, so what's left empty here stays as it was)
        local rule = {}
        for k, v in pairs(applied) do rule[k] = v end
        rule.output = rule_output(m)
        rule.mode = mode or rule.mode or "preferred"
        rule.scale = scale or rule.scale or "auto"
        rule.position = gapped[m.name] or position or rule.position or "auto"
        rule.transform = transform or rule.transform
        if hdr then rule.cm, rule.bitdepth = "hdr", 10 end
        rule.disabled = set_off[m.name] or nil
        if rule.disabled then off[m.name] = rule.output end
        named[rule.output] = rule
        hl.monitor(rule)
    end
end

-- The lid opened or closed (and every load with it closed): each screen whose turn changed set as screens_off says.
-- Last in this file, so neither the host file's rule for the panel nor the refresh rate one above turns it back on at
-- a reload (screens plugged in or unplugged: the lid itself sets its rules without one, below)
function dots.lid(closed, output)
    local lid, set = screens_off(closed, output)
    for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
        if lid[m.name] or set[m.name] and off[m.name] == nil then
            -- Off, by a rule by its name. With no rule by its name before, this one is made from the one that applied (by
            -- make and model, else any screen's): turned on again below, Hyprland starts from it, so the screen comes
            -- back with its mode and scale, not Hyprland's defaults. A rule for it by make and model (the host file's,
            -- the Settings app's) off too, and on again after the one by name: the latest rule matching a screen is the
            -- one applied
            local desc = (m.description or "") ~= "" and named["desc:" .. m.description] and "desc:" .. m.description
            local rule = {}
            for k, v in pairs(not named[m.name] and named[desc or ""] or {}) do rule[k] = v end
            rule.output, rule.disabled = m.name, true
            hl.monitor(rule)
            if desc then hl.monitor({ output = desc, disabled = true }) end
            off[m.name] = desc or false
        elseif not lid[m.name] and not set[m.name] and off[m.name] ~= nil then
            -- On again, only the screens turned off here (a screen this never turned off gets no rule: one by name with
            -- nothing but "on" would be the latest to match it, over the host file's desc: rule). Hyprland's hl.monitor
            -- starts from the rule already there for that same output (the off one above), so its mode and scale stay;
            -- the desc: one last, as the latest rule that matches a screen is the one it applies
            hl.monitor({ output = m.name, disabled = false })
            if off[m.name] then hl.monitor({ output = off[m.name], disabled = false }) end
            off[m.name] = nil
        end
    end
end
if lid_closed() then dots.lid(true) end
-- The switch sets the rule at once, no reload: a reload takes a game out of fullscreen, so it waited for the game, the
-- panel left on (or off) till then. Hyprland 0.57's hl.monitor applies a rule added after the load at the next frame
-- (its monitor rules' scheduled check, not a config reload); the screens changing then has workspaces.lua's reload
-- (after any game, one at a time), and that load reads the lid
hl.bind("switch:on:Lid Switch", function() dots.lid(true) end, { locked = true })
hl.bind("switch:off:Lid Switch", function() dots.lid(false) end, { locked = true })
