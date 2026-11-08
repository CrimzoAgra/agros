-- Screens: layout, refresh rates and colours.
-- Rules for one machine's own screens live in user/hosts/<hostname>.lua; any other screen gets its own resolution at
-- its fastest refresh rate.

-- A rule's "desc:<make and model>" (no serial number in the repo) names the connected screen whose description starts
-- with it: its full description, serial included. Screens come and go with a config reload (workspaces.lua), so this
-- runs again then
local taken, named = {}, {}
function dots.monitor(rule)
    local prefix = (rule.output or ""):match("^desc:(.+)$")
    for _, m in ipairs(prefix and hl.get_monitors() or {}) do
        -- (two screens of one model: each rule gets the next one)
        if (m.description or ""):sub(1, #prefix) == prefix and not taken[m.description] then
            taken[m.description] = true
            rule.output = "desc:" .. m.description
            break
        end
    end
    named[rule.output or ""] = true
    hl.monitor(rule)
end

-- Any other monitor: to the right of the others. Never above or left ("auto-center-up" over a laptop panel): that's
-- negative coordinates, and Proton (Wine) games under XWayland then aim the mouse somewhere else than the pointer.
-- Set before the host file (a screen's own rule wins over this one whatever the order), so a mistake in that file (it
-- stops the rest of this one) still leaves every screen on
dots.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

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
for _, m in ipairs(hl.get_monitors() or {}) do
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
        hl.monitor({ output = m.name, mode = string.format("%dx%d@%.2f", best.width, best.height, best.refresh_rate),
                     position = "auto", scale = "auto" })
    end
end

-- Laptop lid closed with another screen connected: the laptop's own panel (eDP, LVDS or DSI) off, as logind leaves it
-- on then (docked: it doesn't suspend), with workspaces on a dark panel and the pointer wandering onto it. Off by a rule
-- like the ones above: its windows go to the other screen's empty workspaces, and come back when the lid opens
-- (workspaces.lua, as for any screen unplugged). Closed with no other screen: left to logind (it suspends). Last in this
-- file, so neither the host file's rule for the panel nor the refresh rate one above turns it back on at a reload
-- (screens plugged in, or the lid itself). dots.lid(closed, output): output only to try it on a screen that isn't a
-- panel
local function lid_closed()
    local p = io.popen("cat /proc/acpi/button/lid/*/state 2>/dev/null")
    local state = p and p:read("a") or ""
    if p then p:close() end
    return state:find("closed", 1, true) ~= nil
end
function dots.lid(closed, output)
    local panels, others = {}, false
    for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
        if output and m.name == output or not output and (m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI")) then
            panels[#panels + 1] = m
        elseif m.enabled ~= false and m.name ~= "FALLBACK" then  -- (Hyprland's stand-in with no screen at all)
            others = true
        end
    end
    -- Only ever off (at every load the lid is closed at). Not "on" for a panel that's off: no rule here leaves it to the
    -- others, which turn it on as they set it up; one with nothing but "on" replaced them (the host file's mode and scale)
    if not (closed and others) then return end
    for _, m in ipairs(panels) do
        hl.monitor({ output = m.name, disabled = true })
        -- (a host file's rule for it by make and model would win over one by name)
        if named["desc:" .. (m.description or "")] then hl.monitor({ output = "desc:" .. m.description, disabled = true }) end
    end
end
if lid_closed() then dots.lid(true) end
-- (a monitor rule set after the config has loaded does nothing until the next load: the lid reloads it, and the line
-- above reads it then; opened, that load has no rule turning the panel off)
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprctl reload"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl reload"), { locked = true })
