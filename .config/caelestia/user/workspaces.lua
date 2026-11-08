-- Synced workspaces, for any number of screens: each screen gets its own 10 workspaces, in screen order
-- (top to bottom, then left to right): the 1st screen 1-10, the 2nd 11-20, ... Every screen always shows the same
-- column (N on all of them at once), whatever changed it. With one screen it's Caelestia's normal workspaces.
local ok, vars = pcall(require, "variables")  -- Caelestia's settings module; nothing to take over if it's gone
if not ok or type(vars) ~= "table" then vars = {} end

local function screens()
    local list = {}
    for _, m in ipairs(hl.get_monitors() or {}) do list[#list + 1] = m end
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return list
end

local function layout(list)
    local names = {}
    for _, m in ipairs(list or screens()) do names[#names + 1] = m.name end
    return table.concat(names, ",")
end

local function column(id) return (id - 1) % 10 + 1 end

-- The focused screen's place in screen order (and the screens)
local function focused()
    local list, active = screens(), hl.get_active_monitor()
    for k, m in ipairs(list) do
        if active and m.name == active.name then return k, list end
    end
    return 1, list
end

-- The focused screen's column (the 1st when it shows none: a special workspace)
local function current_column()
    local ws = hl.get_active_workspace()
    return ws and (ws.id or 0) > 0 and column(ws.id) or 1
end

-- Column i on every screen. Each screen not on it yet is focused in turn and shown its own workspace of that column
-- (pulled back if another screen had it), then focus goes back. busy: those switches fire workspace.active too, which
-- would sync again from the middle of this
local busy = false
local function show(i)
    local list = screens()
    if #list < 2 then
        return hl.dispatch(hl.dsp.focus({ workspace = i }))
    end
    local current = hl.get_active_monitor()
    local function each()
        local moved = false
        for k, m in ipairs(list) do
            if not (m.active_workspace and m.active_workspace.id == (k - 1) * 10 + i) then
                hl.dispatch(hl.dsp.focus({ monitor = m.name }))
                hl.dispatch(hl.dsp.focus({ workspace = (k - 1) * 10 + i, on_current_monitor = true }))
                moved = true
            end
        end
        if moved and current then hl.dispatch(hl.dsp.focus({ monitor = current.name })) end
    end
    busy = true
    -- (the pointer kept where it is: user/windows.lua)
    local ok, err = pcall(dots.without_warps or function(fn) fn() end, each)
    busy = false
    if not ok then error(err) end
end

-- Caelestia binds Super+N to its own workspace switch: these replace it (a different action, not another key,
-- so not something hypr-vars.lua can change)
-- Only with a modifier (the Settings app can remove it, or set several): bare number keys would be taken
if type(vars.kbGoToWs) == "string" and vars.kbGoToWs:match("%S") then
    for i = 1, 10 do
        local key = vars.kbGoToWs .. " + " .. (i % 10)
        pcall(hl.unbind, key)
        hl.bind(key, function() show(i) end)
    end
end
-- No special workspaces (hypr-vars.lua): Caelestia's touchpad swipes up and down (3 fingers) that open its general one
-- are off too (an empty one came up over the screen). Not under pcall: hl.gesture reports an error as a config error
-- instead of raising it, so a Caelestia update that drops these swipes shows here
for _, dir in ipairs({ "up", "down" }) do
    hl.gesture({ fingers = vars.gestureFingers or 3, direction = dir, action = "unset" })
end
-- The same for scripts: hyprctl eval 'dots.goto_workspace(3)' (the Super+Tab switcher, game-focus, the bar). With
-- synced screens any screen's number (13: the 2nd screen's 3) is that column; with one screen the number as it is
function dots.goto_workspace(i)
    if #screens() >= 2 then i = column(i) end
    show(i)
end

-- Each screen's workspaces live on it (first one = where it starts); reload when screens are plugged/unplugged/moved
local loaded = layout()
local list = screens()
if #list >= 2 then
    for k, m in ipairs(list) do
        for i = 1, 10 do
            hl.workspace_rule({ workspace = tostring((k - 1) * 10 + i), monitor = m.name, default = (i == 1) })
        end
    end
end

-- With synced screens, Caelestia's other workspace keys stay on the focused screen's own 10 (they count across
-- screens: "+1" from the 1st screen's 10 was the 2nd screen's 1, focus jumped screens and the columns parted). Bound
-- with two or more screens only (the config reloads when that changes), so one screen keeps Caelestia's exactly.
-- Next/previous stop at the 1st and 10th (no wrap): a scroll with Super held often goes a notch too far, and from
-- the 10th that would fling you back to the 1st. Moving a window to N puts it on the same screen's N (following it, or
-- not with the silent keys); the group keys (Ctrl+Super+N, Ctrl+Super+scroll) go to screen N, same column
local function own(i) return (focused() - 1) * 10 + i end
local function move(i, follow) hl.dispatch(hl.dsp.window.move({ workspace = own(i), follow = follow })) end
local function to_screen(k)
    local m = screens()[k]
    if m then hl.dispatch(hl.dsp.focus({ monitor = m.name })) end
end
local function keys_of(keys, out)
    out = out or {}
    if type(keys) == "table" then
        for _, k in pairs(keys) do keys_of(k, out) end
    elseif type(keys) == "string" and keys:match("%S") then
        out[#out + 1] = keys
    end
    return out
end
-- The keys Caelestia's own keybinds.lua binds to its launcher's interrupt (Super+scroll stops it opening, in releases
-- that have it): the unbind below takes those too, so they're given back, as Caelestia has them and only then
local function plain(key) return (key:gsub("%s+", ""):lower()) end
local interrupts = {}
-- (where Hyprland reads it: $XDG_CONFIG_HOME or ~/.config; its lines without their -- comments, so a bind commented
-- out doesn't count)
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then config_home = os.getenv("HOME") and os.getenv("HOME") .. "/.config" end
local kb = config_home and io.open(config_home .. "/hypr/hyprland/keybinds.lua")
if kb then
    for line in kb:read("a"):gmatch("[^\n]+") do
        local key = line:gsub("%-%-.*$", "")
            :match('^%s*create_bind%(%s*"([^"]+)"%s*,%s*hl%.dsp%.global%(%s*"caelestia:launcherInterrupt"%s*%)')
        if key then interrupts[plain(key)] = true end
    end
    kb:close()
end
local function rebind(keys, fn, repeating)
    for _, key in ipairs(keys_of(keys)) do
        pcall(hl.unbind, key)
        local mouse = key:lower():find("mouse", 1, true)
        hl.bind(key, fn, repeating and not mouse and { repeating = true } or nil)
        if interrupts[plain(key)] then hl.bind(key, hl.dsp.global("caelestia:launcherInterrupt")) end
    end
end
if #list >= 2 then
    for i = 1, 10 do
        local function with(mods) return type(mods) == "string" and mods:match("%S") and mods .. " + " .. (i % 10) end
        rebind(with(vars.kbMoveWinToWs), function() move(i, true) end)
        rebind(with(vars.kbMoveWinToWsSilent), function() move(i, false) end)
        rebind(with(vars.kbGoToWsGroup), function() to_screen(i) end)
        rebind(with(vars.kbMoveWinToWsGroup), function()
            if screens()[i] then hl.dispatch(hl.dsp.window.move({ workspace = (i - 1) * 10 + current_column() })) end
        end)
    end
    rebind(vars.kbNextWs, function() show(math.min(current_column() + 1, 10)) end, true)
    rebind(vars.kbPrevWs, function() show(math.max(current_column() - 1, 1)) end, true)
    rebind(vars.kbNextWsGroup, function() to_screen(focused() + 1) end, true)
    rebind(vars.kbPrevWsGroup, function() to_screen(focused() - 1) end, true)
    rebind(vars.kbMoveWinToWsNext, function() move(math.min(current_column() + 1, 10), true) end, true)
    rebind(vars.kbMoveWinToWsPrev, function() move(math.max(current_column() - 1, 1), true) end, true)
end
-- Anything else that changes a screen's workspace (a window moved there and followed, the touchpad's swipe, the bar, a
-- script) brings the others to its column. The swipe goes to the screen's own next workspace, except off the end of
-- the 10th, where it makes a new one past every screen's (21 with two): that stays on the 10th, as the keys do.
-- A moment later, once Hyprland is done: the event comes in the middle of a change (a window moved and followed: the
-- other screen still focused), and only if that workspace is still the one its screen shows (else a later change has
-- its own turn). Not while the screens differ from the ones this config was loaded for (until the reload below: no
-- rules for them yet)
hl.on("workspace.active", function(ws)
    local id = ws and ws.id or 0
    if busy or id < 1 then return end
    hl.timer(function()
        if layout() ~= loaded then return end
        local now, w = screens(), hl.get_workspace(id)
        for _, m in ipairs(now) do
            if #now >= 2 and w and w.monitor and m.name == w.monitor.name and m.active_workspace
                and m.active_workspace.id == id then
                return show(id > #now * 10 and 10 or column(id))
            end
        end
    end, { timeout = 1, type = "oneshot" })
end)

-- Screens unplugged and plugged again -----------------------------------------------------------------------------

-- A screen unplugged: each of its workspaces with windows goes to the next empty workspace of the first screen left
-- (not onto the same number, among what's there), and back to that screen when it's plugged in again. What to move
-- back is kept by the screen's make, model and serial (its name when it has none), in Hyprland's own runtime folder
-- (window addresses mean nothing in another session): the config reloads at every screen change, losing anything
-- kept here
local saved_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr/"
                   .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/dots-screens.lua"
local function identity(m) return (m.description or "") ~= "" and m.description or m.name end
local function load_saved()
    local ok, t = pcall(dofile, saved_file)
    return ok and type(t) == "table" and t or {}
end
local function save(t)
    local f = io.open(saved_file, "w")
    if not f then return end
    f:write("return {\n")
    for screen, moved in pairs(t) do
        f:write(string.format("  [%q] = {\n", screen))
        for _, e in ipairs(moved) do
            f:write(string.format("    { address = %q, column = %d, to = %d, minimised = %s },\n",
                                  e.address, e.column, e.to, tostring(e.minimised)))
        end
        f:write("  },\n")
    end
    f:write("}\n")
    f:close()
end
-- A window's workspace: N, or N and true for a minimised one (waiting on special:minimised-N, user/windows.lua). None
-- for a pinned one (the desktop widgets): it shows on every workspace, so it neither moves nor takes one
local function place(w)
    if w.pinned then return end
    local ws = w.workspace or {}
    local min = tonumber((ws.name or ""):match("^special:minimised%-(%d+)$"))
    if min then return min, true end
    if (ws.id or 0) > 0 then return ws.id, false end
end
-- Windows to their new workspaces; a window kept to move back that's still where it was put follows (another screen
-- gone, or the screens renumbered, moves it again)
local function apply(moves, saved)
    local kept = {}
    for _, moved in pairs(saved) do
        for _, e in ipairs(moved) do kept[e.address] = e end
    end
    for _, mv in ipairs(moves) do
        local id, min = place(mv.window)
        local e = kept[mv.window.address]
        if e and e.to == id and e.minimised == min then e.to = mv.to end
        hl.dispatch(hl.dsp.window.move({ window = mv.window, follow = false,
                                         workspace = min and "special:minimised-" .. mv.to or mv.to }))
    end
end

-- The screens changed from before (the ones handled last) to now: every screen still there takes its windows along to
-- its new number (the 2nd becoming the 1st: 11-20 to 1-10, and back), and a gone screen's go to the first screen's
-- empty workspaces, in order (each workspace onto one of its own; once there are none left, the same number)
local before = list
local function renumber(now)
    local moves, saved, index, used, gone = {}, load_saved(), {}, {}, {}
    for k, m in ipairs(now) do index[m.name] = k end
    for _, w in ipairs(hl.get_windows() or {}) do
        local id, min = place(w)
        local ko = id and math.floor((id - 1) / 10) + 1
        local m = ko and before[ko]
        if m then
            local kn, c = index[m.name], column(id)
            if kn then
                if kn ~= ko then moves[#moves + 1] = { window = w, to = (kn - 1) * 10 + c } end
                if kn == 1 then used[c] = true end
            else
                gone[ko] = gone[ko] or {}
                gone[ko][c] = gone[ko][c] or {}
                table.insert(gone[ko][c], { window = w, minimised = min })
            end
        end
    end
    local merged = {}
    for ko = 1, #before do
        if gone[ko] then
            local moved = {}
            for c = 1, 10 do
                if gone[ko][c] then
                    local to = c
                    for e = 1, 10 do
                        if not used[e] then to = e; break end
                    end
                    used[to] = true
                    for _, g in ipairs(gone[ko][c]) do
                        moves[#moves + 1] = { window = g.window, to = to }
                        moved[#moved + 1] = { address = g.window.address, column = c, to = to, minimised = g.minimised }
                    end
                end
            end
            merged[identity(before[ko])] = moved
        end
    end
    apply(moves, saved)
    for screen, moved in pairs(merged) do saved[screen] = moved end
    save(saved)
end

-- (after any game: a reload takes a game out of fullscreen; after-games returns at once when none is open)
-- One reload at a time: a screen plugged in sends two or three events, each reloading on its own otherwise (the reload
-- reads the screens as they are by then, so the ones that find it busy have nothing left to do); then what a
-- returning screen had comes back
local function reload(wait)
    hl.exec_cmd("sleep " .. wait .. "; flock -n \"${XDG_RUNTIME_DIR:-/tmp}/hypr-screens.lock\" sh -c '~/.local/bin/after-games;"
                .. " hyprctl reload; hyprctl eval \"dots.screens_changed()\"'")
end

-- After the reload for a screen plugged in (its workspace rules exist by then): the windows merged away from it go
-- back, only those still where they were put (one you've moved since stays, a closed one is gone); a different screen
-- has nothing kept, so nothing comes to it. Then every numbered workspace onto its own screen (one moved away while its
-- screen was out stays where it went otherwise) and all screens back on one column. hyprctl eval 'dots.screens_changed()'
function dots.screens_changed()
    -- (the screens changed again during the reload, too late for it, as a lid opened right after closing: once more,
    -- after this one's lock is released)
    if layout() ~= loaded then return reload(1) end
    -- (the column shown before: moving a workspace onto its own screen leaves the one it was on another)
    local now, saved, shown = screens(), load_saved(), current_column()
    local moves, any = {}, false
    for k, m in ipairs(now) do
        for _, e in ipairs(saved[identity(m)] or {}) do
            local w = hl.get_window("address:" .. e.address)
            local id, min = place(w or {})
            if w and id == e.to and min == e.minimised then moves[#moves + 1] = { window = w, to = (k - 1) * 10 + e.column } end
        end
        any = any or saved[identity(m)] ~= nil
        saved[identity(m)] = nil
    end
    apply(moves, saved)
    if any then save(saved) end
    if #now < 2 then
        -- (the 2nd screen left alone still shows its 11-20, empty: its windows went to 1-10 with it)
        local ws = hl.get_active_workspace()
        if ws and (ws.id or 0) > 10 then hl.dispatch(hl.dsp.focus({ workspace = column(ws.id) })) end
        return
    end
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        local m = (ws.id or 0) > 0 and now[math.floor((ws.id - 1) / 10) + 1]
        if m and ws.monitor and ws.monitor.name ~= m.name then
            hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = m.name }))
        end
    end
    show(shown)
end

local function recheck()
    -- Only when the screens change, not at every load; from the ones handled last (two or three events per screen
    -- plugged in; unplugged and plugged back before the reload)
    local now = screens()
    if layout(now) == layout(before) then return end
    if #before >= 2 or #now >= 2 then renumber(now) end
    before = now
    reload(0)
end
hl.on("monitor.added", recheck)
hl.on("monitor.removed", recheck)
hl.on("monitor.layout_changed", recheck)
