-- Windows, Windows-style: floating by default (a floating/tiling switch in the bar's right-click menu), opening in the
-- middle at one standard size, minimise and maximise (keys, the title bar buttons of titlebars.lua, apps' own), and
-- the clicked or picked window to the front.
-- Called from outside this file through hyprctl eval 'dots.<name>(...)': focus_window (Alt+Tab switcher, dock,
-- game-focus), focus_app (a click on a notification), minimise_window and
-- maximise_window (title bar buttons),
-- toggle_window_mode (bar menu, the Settings app's window mode), refit_placed_soon (Caelestia's bar, its space changed:
-- the overlay's bar_space_refit), peek_screen and peek_end (window peek: the overlay's WindowPeek.qml),
-- window_drag_start, window_drag_step, window_drag_end and titlebar_drag_start (the title bar plugin, my patch to it:
-- ~/.local/share/hyprbars/hyprbars.patch, which also gives hl.plugin.hyprbars.min_size). Caelestia is told of drags
-- through Hyprland's custom events ("agros_drag 1/0", "agros_snap <screen> x y w h" / "agros_snap none": its
-- WindowDrag.qml). And from this file itself, a moment later (a sleep in its own process: a config reload would drop a
-- timer): refit_maximised, window_fades, open_retry
-- Caelestia's settings module (gaps, border): its defaults if an update renames it, not this whole file failing
local ok, vars = pcall(require, "variables")
if not ok or type(vars) ~= "table" then vars = {} end
-- Hyprland's gaps and border as they are now (Caelestia's Game mode sets them at runtime; its variables keep the ones
-- configured): a gap's largest side, as the title bar plugin reads them, so snapping and its seams agree with it
local function live(key, fallback)
    local v = hl.get_config and hl.get_config(key)
    if type(v) == "table" then
        local m
        for _, x in pairs(v) do if type(x) == "number" and (not m or x > m) then m = x end end
        return m or fallback
    end
    return type(v) == "number" and v or fallback
end
local function gaps_in() return live("general.gaps_in", vars.windowGapsIn or 5) end
local function gaps_out() return live("general.gaps_out", vars.windowGapsOut or 10) end
local function border() return live("general.border_size", vars.windowBorderSize or 2) end

local function by_address(address)
    return hl.get_window("address:" .. address)
end

-- A floating window comes to the front when clicked or picked, not when the pointer only focuses it (Hyprland leaves
-- it under the others)
local function raise(win)
    if win and win.floating then hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = win })) end
end

-- A maximised window carries the tag "maximised" (hyprctl clients shows it; the title bar's maximise button shows a
-- restore icon by it): kept on the window itself, so unlike a list here it survives config reloads
local function has_tag(win, tag)
    for _, t in ipairs(win.tags or {}) do
        if t == tag then return true end
    end
    return false
end
local function is_maximised(win) return has_tag(win, "maximised") end
local function set_maximised(win, on)
    hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. "maximised", window = "address:" .. win.address }))
end

-- A value to the nearest pixel
local function px(v) return math.floor(v + 0.5) end
-- A screen's size in the units windows are placed in: its mode over its scale, width and height swapped when it's
-- turned sideways (Hyprland gives the mode as it is, not turned). Whole: Hyprland keeps a screen's size in those units
-- whole, but gives its scale as a float (1.6 as 1.60000002), and the fraction left made every refit's proportion off
-- by a hair, so seams crept
local function screen_size(m)
    local w, h = px(m.width / m.scale), px(m.height / m.scale)
    if (m.transform or 0) % 2 == 1 then return h, w end
    return w, h
end

-- Maximised: the screen inside the same gaps as tiled windows (the wallpaper still shows round it), with room for the
-- window's title bar (titlebars.lua, while the plugin is on)
local function maximised_box(win, m)
    m = m or win.monitor or hl.get_active_monitor()
    local r, edge = m.reserved, gaps_out() + border()
    local bar = dots.titlebar_height and dots.titlebar_height(win) or 0
    local mw, mh = screen_size(m)
    return { x = m.x + r.left + edge, y = m.y + r.top + edge + bar,
             w = mw - r.left - r.right - 2 * edge,
             h = mh - r.top - r.bottom - 2 * edge - bar }
end
-- The size windows open and un-maximise to: the maximised window's shape at 60% of the screen's height, in the middle
-- with its title bar. An app with a size of its own (a minimum, or a fixed one) stops there
local function standard_box(win)
    local m, full = win.monitor or hl.get_active_monitor(), maximised_box(win)
    local mw, mh = screen_size(m)
    local bar = dots.titlebar_height and dots.titlebar_height(win) or 0
    local height = mh * 0.6
    local width = height * full.w / full.h
    return { x = m.x + (mw - width) / 2, y = m.y + (mh - height + bar) / 2, w = width, h = height }
end
-- (its edges rounded, not its place and size each: a box ending on a screen's border ends there, not a pixel short;
-- to the nearest pixel (px), so a box worked out from a placed one, then placed, doesn't creep one way)
local function place(win, box)
    local x, y = px(box.x), px(box.y)
    hl.dispatch(hl.dsp.window.resize({ x = px(box.x + box.w) - x, y = px(box.y + box.h) - y, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = win }))
end
-- Windows opened (or floated by a switch) one after another, none moved meanwhile: each one a step down and right of the one before, as on
-- Windows, so none hides another (a window that's been moved frees its spot). The step is the title bar's height, so
-- every title shows; past the screen's edge it starts from the middle again. Off in the Settings app: all in the middle
local function cascaded(win, box)
    if dots.setting("windows.cascade") == false then return box end
    local m = win.monitor or hl.get_active_monitor()
    local step = dots.titlebar_height and dots.titlebar_height(win) or 0
    if step == 0 then step = 32 end
    local rounds = 0
    for _ = 1, 50 do
        local taken = false
        for _, w in ipairs(hl.get_windows() or {}) do
            if w.address ~= win.address and w.floating and w.workspace and w.workspace.name == win.workspace.name
                and math.abs(w.at.x - math.floor(box.x)) <= 2 and math.abs(w.at.y - math.floor(box.y)) <= 2 then
                taken = true
                break
            end
        end
        if not taken then return box end
        box.x, box.y = box.x + step, box.y + step
        local mw, mh = screen_size(m)
        if box.x + box.w > m.x + mw or box.y + box.h > m.y + mh then
            -- Past the edge: from the middle again, half a step further right each round (not all on the middle one)
            rounds = rounds + 1
            box = standard_box(win)
            box.x = box.x + rounds * step / 2
        end
    end
    return box
end
-- Snapping's state (Snapping, below): the size each snapped window had before (address -> w, h; lost on a reload: the
-- standard size then), and its tags taken off. A window placed another way (maximised, floated by the switch) is no
-- longer snapped: else a screen change put it back in its zone, and its next drag took an old size
local snap_before, unsnap = {}, nil
local function forget_snap(win)
    unsnap(win)
    snap_before[win.address] = nil
end
-- Where a window goes when it starts floating (it opens, or a switch floats it): maximised windows (tagged) to the
-- maximised box, any other to the standard size, cascading
local function place_floating(win)
    forget_snap(win)
    place(win, is_maximised(win) and maximised_box(win) or cascaded(win, standard_box(win)))
end

-- The desktop's window mode: floating (the default) or tiling. The bar menu (BarMenu.qml in
-- ~/.local/share/caelestia-overlay) reads it from this file
local mode_file = os.getenv("HOME") .. "/.local/state/window-mode"
local function window_mode()
    local f = io.open(mode_file)
    if not f then return "floating" end
    local mode = f:read("l")
    f:close()
    return mode == "tiling" and "tiling" or "floating"
end
-- Floating, as on Windows: the pointer stays where it is when another window is focused, and focus changes on a click,
-- not on hover (follow_mouse 2; scrolling still reaches the window under the pointer). With focus following the
-- pointer, the window under it took focus back right after an Alt+Tab pick when the mouse had moved meanwhile.
-- Focus on hover in floating mode too if chosen in the Settings app (windows.focus). With focus on a click, a window
-- closed passes the focus to the one used before it there (Hyprland's focus_on_close "mru", as on Windows), not to the
-- one under the pointer (Caelestia's dots' 1, kept with focus on hover): with the pointer on the desktop, nothing had
-- the focus after a close though windows were left, and the next Super+Q did nothing
local function apply_mode_settings(mode)
    local floating = mode == "floating"
    local click = floating and dots.setting("windows.focus") ~= "hover"
    hl.config({ cursor = { no_warps = floating },
                input = { follow_mouse = click and 2 or 1, focus_on_close = click and 2 or 1 } })
end

-- fn run with the pointer left where it is: Super+N's sync focuses each screen in turn (workspaces.lua), and in tiling
-- mode each focus moved the pointer, ending in the middle of the screen, where focus followed it to another window
function dots.without_warps(fn)
    hl.config({ cursor = { no_warps = true } })
    local ok, err = pcall(fn)
    apply_mode_settings(window_mode())
    if not ok then error(err) end
end
apply_mode_settings(window_mode())

-- Windows resize by dragging their edges, as on Windows: from just outside the 1-px border, 15 px out (Hyprland's
-- extend_border_grab_area: it spans the gaps), and the rounded corners. Floating and tiled windows alike, not
-- fullscreen ones (nor a tiled one Hyprland maximised); a maximised one stops being maximised (dots.window_drag_start).
-- With the title bar plugin (my patch), an edge moves only that edge (Hyprland's own moves the nearest corner), and a
-- window with a bar resizes upwards from the bar's top. Hyprland has it off by default, and Caelestia doesn't set it.
-- Off while a game is open (apps.lua: its border band reached the next screen and the screen's corners)
hl.config({ general = { resize_on_border = true } })

-- Raising -------------------------------------------------------------------------------------------------------------

-- A left-click bind that lets the click through, raising the clicked window once Hyprland has focused it (it does so
-- while handling the click, after this bind). Not right away: the active window isn't always the one under the pointer
-- (just after Alt+Tab, with the pointer still on another window), and that one went to the front instead
hl.bind("mouse:272", function()
    hl.timer(function() raise(hl.get_active_window()) end, { timeout = 1, type = "oneshot" })
end, { non_consuming = true })

-- Windows' fade in (Hyprland hides the rest of a workspace behind a fullscreen window, and fades it back in when that
-- one goes: the bare desktop showed first). Off while Alt+Tab leaves a fullscreen game, on again a moment later, as
-- animations.lua has it (the "fade" speed and curve)
function dots.window_fades(on)
    for _, leaf in ipairs({ "fadeIn", "fadeSwitch" }) do
        hl.animation({ leaf = leaf, enabled = on, speed = 6, bezier = "standard" })
    end
end

-- The window picked in the Alt+Tab switcher or the dock: focused and to the front. A minimised one comes back too
-- (the focus hook below)
-- switcher: picked with Alt+Tab, which minimises a fullscreen window you leave (a game), as on Windows; it comes back
-- fullscreen from the switcher, the dock or the restore key (Super+Alt+M)
function dots.focus_window(address, switcher)
    local win = by_address(address)
    if not win then return end
    local active = hl.get_active_window()
    -- Fullscreen proper (2; 1 is maximised), and only when the pick is on its screen (one on another screen doesn't
    -- cover it)
    if switcher and active and active.address ~= win.address and (active.fullscreen or 0) >= 2
        and active.monitor and win.monitor and active.monitor.id == win.monitor.id then
        dots.window_fades(false)
        dots.minimise_window(active)
        hl.exec_cmd("sh -c 'sleep 0.5; exec hyprctl eval \"dots.window_fades(true)\"'")
    end
    hl.dispatch(hl.dsp.focus({ window = win }))
    raise(win)  -- this window, not "the active one": that may not be it yet right after the focus
end

-- Clicking a notification brings the app that sent it to the front, as on Windows (Caelestia's notifications call this:
-- the overlay's notif_click): its most recently used window, by class, matched to the notification's desktop entry or
-- app name (e.g. com.spotify.Client and spotify), or by a title that is exactly the name. With no window, the app is opened. Apps can't raise themselves from
-- a notification: Caelestia gives them no activation token
function dots.focus_app(entry, name, launch)
    local wanted = {}
    for _, n in ipairs({ entry or "", name or "" }) do
        if #n >= 3 then wanted[#wanted + 1] = n:lower() end
    end
    -- An exact class first (steam is Steam, not the game steam_app_123); then a class within the name or the name
    -- within a class, or a title that is just the name (games keep it: Overwatch's class is steam_app_2357570).
    -- Among those, the most recently used: a window never focused (-1: a launcher minimised as it opened, a window
    -- opened in the background) comes last, not first
    local function recency(w)
        local id = w.focus_history_id or -1
        return id < 0 and math.huge or id
    end
    local best, best_rank
    for _, w in ipairs(hl.get_windows() or {}) do
        local class, title = (w.class or ""):lower(), (w.title or ""):lower()
        for _, n in ipairs(wanted) do
            local rank = (#class >= 3 and class == n) and 1
                or ((#class >= 3 and (n:find(class, 1, true) or class:find(n, 1, true))) or title == n) and 2
            if rank and (not best or rank < best_rank or (rank == best_rank and recency(w) < recency(best))) then
                best, best_rank = w, rank
            end
        end
    end
    if best then return dots.focus_window(best.address) end
    -- launch false: the notification's own action ran, which may open the app itself (opening it as well could undo
    -- that): look again in a moment, and open it only if nothing came up (the app had quit, the action went nowhere)
    if launch == false then
        return hl.timer(function() dots.focus_app(entry, name, true) end, { timeout = 1500, type = "oneshot" })
    end
    if entry and entry:match("^[%w%.%-_]+$") then hl.exec_cmd("~/.local/bin/app-launch gtk-launch " .. entry) end
end

-- Minimise ------------------------------------------------------------------------------------------------------------

-- Super+M, the title bar button, or an app's own minimise (the few that ask: GTK apps don't, as Hyprland has no
-- minimise to offer them). Hyprland has none itself, so a minimised window waits on a hidden special workspace per
-- workspace (special:minimised-N for workspace N). The bar dock and the switchers keep showing it on workspace N;
-- clicking or picking it there, or Super+Alt+M (the last one minimised on this workspace), brings it back
local minimised = {}  -- addresses, most recent last
function dots.minimise_window(win)
    win = win or hl.get_active_window()
    if not (win and win.workspace) or (win.workspace.id or 0) < 1 then return end  -- not already in a special workspace
    -- The list keeps only windows still minimised (restored through the dock, or closed, they'd pile up)
    for i = #minimised, 1, -1 do
        local w = hl.get_window("address:" .. minimised[i])
        if minimised[i] == win.address or not (w and w.workspace and (w.workspace.name or ""):find("^special:minimised%-")) then
            table.remove(minimised, i)
        end
    end
    table.insert(minimised, win.address)
    -- A pinned window (picture-in-picture: Caelestia pins it; Super+P) Hyprland keeps out of special workspaces, so
    -- minimising did nothing: unpinned to go, and pinned again as it comes back (the tag "minimised_pinned")
    if win.pinned then
        hl.dispatch(hl.dsp.window.pin({ action = "off", window = win }))
        hl.dispatch(hl.dsp.window.tag({ tag = "+minimised_pinned", window = "address:" .. win.address }))
    end
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimised-" .. win.workspace.id, follow = false, window = win }))
end
-- Moved off its hidden workspace, a window coming back hands the focus to another on its workspace for a moment (its
-- hidden one closing): no app focused over a game (off_game), which minimised a game again as it came back, left on
-- its hidden workspace shown over the screen with the shell over it (the dock, Super menu open)
local restoring = false
local function restore(win, ws)
    restoring = true
    local ok, err = pcall(function()
        hl.dispatch(hl.dsp.window.move({ workspace = ws, window = win }))
        dots.refit_window(by_address(win.address))
        if has_tag(win, "minimised_pinned") then
            hl.dispatch(hl.dsp.window.tag({ tag = "-minimised_pinned", window = "address:" .. win.address }))
            hl.dispatch(hl.dsp.window.pin({ action = "on", window = win }))
        end
        hl.dispatch(hl.dsp.focus({ window = win }))
        raise(win)
    end)
    restoring = false
    if not ok then error(err, 0) end
end
dots.bind("minimise", function() dots.minimise_window() end)
-- An app's own request: to minimise, or (false) to come back, which isn't one to minimise
-- (no window: nothing, not the focused one minimise_window would take)
-- Not a game's: games ask on losing focus (clicking Capri, a notification), then stop drawing as if minimised, so
-- they came back black; Alt+Tab and the minimise key still minimise them, without the game being told
hl.on("window.minimize", function(win, on)
    if win and on ~= false and on ~= 0 and not (dots.is_game and dots.is_game(win)) then dots.minimise_window(win) end
end)
dots.bind("restore", function()
    local ws, waiting = hl.get_active_workspace(), {}
    if not ws then return end
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.workspace and w.workspace.name == "special:minimised-" .. ws.id then waiting[w.address] = w end
    end
    -- The last one minimised on this workspace (the others' stay listed)
    local win
    for i = #minimised, 1, -1 do
        if waiting[minimised[i]] then
            win = waiting[table.remove(minimised, i)]
            break
        end
    end
    if not win then win = select(2, next(waiting)) end  -- the list is lost on a reload: any of them
    if win then restore(win, ws.id) end
end)
-- Focusing a minimised window (the dock does) would open its hidden workspace on top of the screen: it comes back
-- onto its own workspace instead
hl.on("window.active", function(win)
    local ws = win and win.workspace and tonumber((win.workspace.name or ""):match("^special:minimised%-(%d+)$"))
    if ws then restore(win, ws) end
end)

-- Maximise ------------------------------------------------------------------------------------------------------------

-- A screen added or removed moves workspaces to other screens: windows fit the screen they're on now (dots.refit_maximised,
-- below with snapping). After a moment, once the workspaces have moved; from a process of its own, as workspaces.lua
-- reloads the config on a screen change, which drops a timer here
local function refit_soon() hl.exec_cmd("sh -c 'sleep 1.5; exec hyprctl eval \"dots.refit_maximised()\"'") end
hl.on("monitor.added", refit_soon)
hl.on("monitor.removed", refit_soon)

-- Super+Alt+F, the title bar button, or an app's own maximise. A floating window goes to the maximised box and back to
-- the standard size; a tiled window gets Hyprland's maximise
function dots.maximise_window(win)
    win = win or hl.get_active_window()
    if not win then return end
    if not win.floating then return hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", window = win })) end
    local maximised = is_maximised(win)
    forget_snap(win)
    set_maximised(win, not maximised)
    place(win, maximised and standard_box(win) or maximised_box(win))
end
dots.bind("maximise", function() dots.maximise_window() end)
-- An app's own maximise makes Hyprland maximise a floating window edge to edge, over the gaps: undo that and do the
-- above. The app is told it isn't maximised, so its button stays "maximise" and the next click puts it back
hl.on("window.fullscreen", function(win)
    -- A game that opened fullscreen stayed tiled (on_open leaves fullscreen windows be): floating mode floats it once it
    -- leaves fullscreen, as on_open would have (else it tiled, and so did every window opened next to it). Its floating
    -- box is the whole screen: Hyprland takes a fullscreen window out of fullscreen for an instant to move it (Alt+Tab
    -- minimising it, bringing it back), and the game drew a frame at a smaller floating size, shown with black bars
    if win and win.fullscreen == 0 and dots.is_game and dots.is_game(win) and window_mode() == "floating"
        and win.workspace and (win.workspace.id or 0) > 0 then
        if not win.floating then hl.dispatch(hl.dsp.window.float({ action = "on", window = win })) end
        local m = win.monitor or hl.get_active_monitor()
        local w, h = screen_size(m)
        place(win, { x = m.x, y = m.y, w = w, h = h })
        return
    end
    if not (win and win.floating and win.fullscreen == 1) then return end
    if dots.is_game and dots.is_game(win) then return end  -- a game keeps Hyprland's edge-to-edge (on_open's reason)
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    dots.maximise_window(win)
end)
-- Dragging a maximised window un-maximises it, as on Windows. Moved (by its title bar, the plugin's or the app's own:
-- GTK header bars, Electron's, Qt's; or Super+drag): to the standard size, the pointer kept at the same place along
-- the title bar. Resized (its edges, Super+right-drag): just no longer maximised, from the size it had, so the title bar
-- button shows "maximise" again and a title bar drag doesn't shrink it. The title bar plugin calls this as any drag of
-- a window starts (my patch hooks Hyprland's drag start), so the drag goes on from the new size. Apps can't do it
-- themselves: Hyprland never tells them they're maximised. Without the plugin, a drag leaves it maximised in name
local snap_drag_start, snap_drag_end, keep_reachable  -- (Snapping and Always within reach, below)
local game_drags = {}  -- (fullscreen games being dragged, by address: fullscreen again where they're dropped)
function dots.window_drag_start(address, kind)
    local win = by_address(address)
    if not win then return end
    -- A fullscreen game (or one as big as its screen: Hyprland takes it out of fullscreen to drag it, and the handler
    -- above floats it at the screen's size)
    if kind == "move" and dots.is_game and dots.is_game(win) then
        local m = win.monitor or hl.get_active_monitor()
        local w, h = m and screen_size(m)
        game_drags[address] = (win.fullscreen or 0) > 0 or (w and win.size.x >= w - 1 and win.size.y >= h - 1) or nil
    end
    -- A snapped window (below) dragged away: back to the size it had before it was snapped (Windows' way); a maximised
    -- one too, when it was snapped there (else to the standard size)
    local before = snap_drag_start(win, kind)
    if not (win.floating and (is_maximised(win) or before)) then return end
    if is_maximised(win) then set_maximised(win, false) end
    if kind ~= "move" then return end
    local box, cursor = standard_box(win), hl.get_cursor_pos()
    if before then box.w, box.h = before.w, before.h end
    box.x = cursor.x - box.w * (cursor.x - win.at.x) / win.size.x
    -- The pointer as far below the top as before (on the title bar), or as far down in proportion when the smaller
    -- window can't keep that (a Super+drag low in it)
    local dy = cursor.y - win.at.y
    if dy > box.h then dy = box.h * dy / win.size.y end
    box.y = cursor.y - dy
    place(win, box)
end
-- The plugin's own bar calls this "before" its drag starts (and "after", unused: an animated shrink there didn't last,
-- the drag keeps the size it began with). The same as the hook above, for a plugin build without it
function dots.titlebar_drag_start(address, phase)
    if phase ~= "after" then dots.window_drag_start(address, "move") end
end

-- Snapping ------------------------------------------------------------------------------------------------------------

-- As on Windows: a floating window let go with the pointer at a screen's top edge is maximised; at its left, right or
-- bottom edge it takes that half; in a corner, that quarter (near a corner: the last sixth of the edge). A see-through preview
-- shows where while it's dragged (Caelestia's drawers draw it: SnapPreview.qml in ~/.local/share/caelestia-overlay, told
-- through Hyprland's custom events, "agros_snap <screen> x y w h" or "agros_snap none"), and Caelestia's panels don't
-- open meanwhile ("agros_drag 1"/"agros_drag 0"). Dragged away, it gets back the size it had. Snapped windows next to
-- each other share their seam: resizing one moves the other's edge with it, in the same frame, as tiled windows do (the
-- plugin calls dots.window_drag_step after each step of a drag), with a two-way resize cursor over the gap (the plugin's).
-- Floating mode only (tiling places windows itself), not games nor fullscreen windows. Drags reach here from the title
-- bar plugin (my patch: dots.window_drag_start and dots.window_drag_end); without it, no snapping
-- Its zone is kept on the window, as maximised is (tags: "snapped", "snap_<zone>", and "snaparea_..." for the free
-- part it was placed for: set_area, below), so it survives the config
-- reloads (a screen plugged in reloads it) and a screen change re-fits it there. A closed window's size before is
-- dropped (a new window may get its address)
local snap_zone, snap_screen, follow, moving = nil, nil, nil, false  -- (moving: a snappable window's move is going on)
hl.on("window.close", function(win) if win then snap_before[win.address] = nil end end)

-- The free part of a screen (inside its reserved space and the outer gaps), and the gap between two snapped windows
-- (as between tiled ones: both inner gaps and both borders)
local function snap_area(m)
    local r, edge = m.reserved, gaps_out() + border()
    local mw, mh = screen_size(m)
    return { x = m.x + r.left + edge, y = m.y + r.top + edge,
             w = mw - r.left - r.right - 2 * edge, h = mh - r.top - r.bottom - 2 * edge }
end
local function seam() return 2 * (gaps_in() + border()) end

-- The zone the pointer is in on its screen, or nil; and its box there (with the title bar: the window goes below it)
local zones = { left = { 0, 0, 1, 2 }, right = { 1, 0, 1, 2 }, bottom = { 0, 1, 2, 1 }, tl = { 0, 0, 1, 1 },
                tr = { 1, 0, 1, 1 }, bl = { 0, 1, 1, 1 }, br = { 1, 1, 1, 1 },
                top = { 0, 0, 2, 1 } }  -- column, row, columns wide, rows high (of 2 x 2). (top: Snap Assist's only, below)
-- Another screen at that point (beside or above this one: a window, or the pointer, may go on across there)
local function screen_beyond(m, px, py)
    for _, o in ipairs(hl.get_monitors() or {}) do
        if o.name ~= m.name then
            local ow, oh = screen_size(o)
            if px >= o.x and px < o.x + ow and py >= o.y and py < o.y + oh then return true end
        end
    end
    return false
end
-- The edges are the free part's (inside Caelestia's border and bar: the title bar plugin keeps a dragged window's
-- pointer there, as a screen's edge would) or past them; not a side with another screen beyond, where the pointer goes
-- on across (the preview flashed on the way over, and a drop there snapped)
local function zone_at(m, c)
    local mw, mh = screen_size(m)
    local x, y, r = c.x - m.x, c.y - m.y, m.reserved
    local left, right, top, bottom = x <= r.left + 1, x >= mw - r.right - 2, y <= r.top + 1, y >= mh - r.bottom - 2
    left = left and not screen_beyond(m, m.x - 1, c.y)
    right = right and not screen_beyond(m, m.x + mw, c.y)
    top = top and not screen_beyond(m, c.x, m.y - 1)
    bottom = bottom and not screen_beyond(m, c.x, m.y + mh)
    local near_top, near_bottom = y < mh / 6, y > mh * 5 / 6
    local near_left, near_right = x < mw / 6, x > mw * 5 / 6
    if (left and near_top) or (top and near_left) then return "tl" end
    if (right and near_top) or (top and near_right) then return "tr" end
    if (left and near_bottom) or (bottom and near_left) then return "bl" end
    if (right and near_bottom) or (bottom and near_right) then return "br" end
    if top then return "max" end
    if left then return "left" end
    if right then return "right" end
    if bottom then return "bottom" end
end
local function zone_box(m, zone)
    local a, g = snap_area(m), seam()
    if zone == "max" then return a end
    local z = zones[zone]
    local cw, ch = (a.w - g) / 2, (a.h - g) / 2
    return { x = a.x + z[1] * (cw + g), y = a.y + z[2] * (ch + g),
             w = z[3] * cw + (z[3] - 1) * g, h = z[4] * ch + (z[4] - 1) * g }
end

local function snappable(win)
    return win and win.floating and (win.fullscreen or 0) == 0 and window_mode() == "floating"
        and not (dots.is_game and dots.is_game(win)) and win.workspace and (win.workspace.id or 0) > 0
end
local function tell(event) hl.dispatch(hl.dsp.event(event)) end
-- The zone under the pointer and its screen (where the window goes: the pointer's, not the one most of the window is
-- on), the preview told when either changes
local function update_zone()
    local m, c = hl.get_monitor_at_cursor(), hl.get_cursor_pos()
    local zone = m and c and zone_at(m, c) or nil
    local screen = zone and m.name or nil
    if zone == snap_zone and screen == snap_screen then return end
    snap_zone, snap_screen = zone, screen
    if not zone then return tell("agros_snap none") end
    -- (rounded as place() rounds the window that goes there)
    local b = zone_box(m, zone)
    local x, y = px(b.x), px(b.y)
    tell(string.format("agros_snap %s %d %d %d %d", m.name, x - m.x, y - m.y, px(b.x + b.w) - x, px(b.y + b.h) - y))
end

-- A box as the window has it (below its title bar) and the edges it shares with a snapped neighbour
local function outer(w)
    local bar = dots.titlebar_height and dots.titlebar_height(w) or 0
    return { x = w.at.x, y = w.at.y - bar, w = w.size.x, h = w.size.y + bar, bar = bar }
end
-- The windows on each of the window's seams. A seam is a line: every snapped window with an edge on it (the window's
-- own edge, "same", or across the gap from it, "sides") that joins up along it, so the whole line moves together
-- (with four quarters, resizing the top left one against the top right one moves the bottom row's seam too)
local function neighbours(win)
    local o, g, found = outer(win), seam(), {}
    local function near(a, b) return math.abs(a - b) <= 3 end
    local others = {}
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.address ~= win.address and has_tag(w, "snapped") and w.floating and w.workspace and win.workspace
            and w.workspace.id == win.workspace.id then
            others[#others + 1] = { address = w.address, box = outer(w) }
        end
    end
    local by = {}
    local function entry(n)
        if not by[n.address] then
            by[n.address] = { address = n.address, box = n.box, sides = {}, same = {} }
            found[#found + 1] = by[n.address]
        end
        return by[n.address]
    end
    -- side: which of the window's edges; line: where it is; along: the span along it (y for a side edge, x for top or
    -- bottom); edge_same/edge_across: a window's edge on the line on this side / across the gap
    local function line(side, opposite, at, lo, hi, same_at, across_at)
        local spans, picked, grew, list, seam_here = { { lo(o), hi(o) } }, {}, true, {}, false
        while grew do
            grew = false
            for _, n in ipairs(others) do
                if not picked[n.address] then
                    local same, across = near(same_at(n.box), at), near(across_at(n.box), at)
                    local touches = false
                    for _, sp in ipairs(spans) do
                        if lo(n.box) <= sp[2] + g + 3 and hi(n.box) >= sp[1] - g - 3 then touches = true end
                    end
                    if (same or across) and touches then
                        picked[n.address], grew = true, true
                        spans[#spans + 1] = { lo(n.box), hi(n.box) }
                        list[#list + 1] = { n = n, same = same }
                        seam_here = seam_here or not same
                    end
                end
            end
        end
        -- (a seam only with a window across it: the screen's edge, windows only lined up along it, isn't one)
        if not seam_here then return end
        for _, p in ipairs(list) do
            local e = entry(p.n)
            if p.same then e.same[side] = true else e.sides[side] = opposite end
        end
    end
    local function y0(b) return b.y end
    local function y1(b) return b.y + b.h end
    local function x0(b) return b.x end
    local function x1(b) return b.x + b.w end
    line("right", "left", o.x + o.w, y0, y1, x1, function(b) return b.x - g end)
    line("left", "right", o.x, y0, y1, x0, function(b) return b.x + b.w + g end)
    line("bottom", "top", o.y + o.h, x0, x1, y1, function(b) return b.y - g end)
    line("top", "bottom", o.y, x0, x1, y0, function(b) return b.y + b.h + g end)
    return found
end

-- The neighbours' shared edges follow the resized window's (each step of the drag); window moves unanimated meanwhile,
-- or each step animated after the pointer. The seam stops where either window can't shrink further, as with tiled ones:
-- Hyprland stops the resized one at its app's smallest size, and a neighbour at its own (the title bar plugin tells it:
-- hl.plugin.hyprbars.min_size), the resized one held back to it
local function min_size(w)
    local f = hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.min_size
    local mw, mh = 1, 1
    if f then mw, mh = f(w.address) end
    return math.max(mw or 1, 50), math.max(mh or 1, 50)
end
local function follow_step()
    local win = follow and by_address(follow.address)
    if not win then return end
    local now, g = outer(win), seam()
    -- The resized window's edges, held back where a neighbour (or one along the seam) is at its smallest; then each
    -- placed from them, only when it changed (not every step: its app asked to resize for nothing)
    local L, R, T, B = now.x, now.x + now.w, now.y, now.y + now.h
    local list = {}
    for _, n in ipairs(follow.with) do
        local w = by_address(n.address)
        if w then
            local mw, mh = min_size(w)
            mh = mh + n.box.bar
            local nb = n.box
            if n.sides.right then R = math.min(R, nb.x + nb.w - mw - g) end
            if n.sides.left then L = math.max(L, nb.x + mw + g) end
            if n.sides.bottom then B = math.min(B, nb.y + nb.h - mh - g) end
            if n.sides.top then T = math.max(T, nb.y + mh + g) end
            if n.same.right then R = math.max(R, nb.x + mw) end
            if n.same.left then L = math.min(L, nb.x + nb.w - mw) end
            if n.same.bottom then B = math.max(B, nb.y + mh) end
            if n.same.top then T = math.min(T, nb.y + nb.h - mh) end
            list[#list + 1] = { w = w, n = n }
        end
    end
    for _, e in ipairs(list) do
        local n, nb = e.n, e.n.box
        -- (each of its edges on its own: one on a seam follows it, the rest stay)
        local l, r, t, bt = nb.x, nb.x + nb.w, nb.y, nb.y + nb.h
        if n.sides.right then l = R + g end
        if n.sides.left then r = L - g end
        if n.sides.bottom then t = B + g end
        if n.sides.top then bt = T - g end
        if n.same.right then r = R end
        if n.same.left then l = L end
        if n.same.bottom then bt = B end
        if n.same.top then t = T end
        local b = { x = l, y = t, w = r - l, h = bt - t }
        local last = n.last or nb
        if b.x ~= last.x or b.y ~= last.y or b.w ~= last.w or b.h ~= last.h then
            place(e.w, { x = b.x, y = b.y + nb.bar, w = b.w, h = b.h - nb.bar })
            n.last = b
        end
    end
    -- (held back: a neighbour at its smallest)
    if L ~= now.x or T ~= now.y or R ~= now.x + now.w or B ~= now.y + now.h then
        place(win, { x = L, y = T + now.bar, w = R - L, h = B - T - now.bar })
    end
end

-- The screen and its free part a snapped window was last placed for, kept on the window as its zone is (a tag,
-- "snaparea_<screen>_<x>_<y>_<w>_<h>_<seam>_<title bar>", relative to the screen: config reloads, which a VM's resize
-- and a screen plugged in make, keep it), for a screen change to keep seams where they were dragged to, in proportion,
-- a change of the gaps (Caelestia's Game mode) to keep them where they were, the gap across them the new one, and title
-- bars turned on or off (the Settings app) to fit the window under its bar, or without it, in the same place
local function bar_of(win) return dots.titlebar_height and dots.titlebar_height(win) or 0 end
local function set_area(win, m)
    local a = snap_area(m)
    local tag = string.format("snaparea_%s_%d_%d_%d_%d_%d_%d", m.name, math.floor(a.x - m.x), math.floor(a.y - m.y),
        math.floor(a.w), math.floor(a.h), math.floor(seam()), bar_of(win))
    local list = {}
    for _, t in ipairs(win.tags or {}) do list[#list + 1] = t end
    for _, t in ipairs(list) do
        if t:match("^snaparea_") and t ~= tag then hl.dispatch(hl.dsp.window.tag({ tag = "-" .. t, window = "address:" .. win.address })) end
    end
    if not has_tag(win, tag) then hl.dispatch(hl.dsp.window.tag({ tag = "+" .. tag, window = "address:" .. win.address })) end
end
local function recorded_area(win, m)
    for _, t in ipairs(win.tags or {}) do
        local name, x, y, w, h, g, bar = t:match("^snaparea_(.+)_(%-?%d+)_(%-?%d+)_(%d+)_(%d+)_(%d+)_(%d+)$")
        if name then
            if name ~= m.name then return nil end
            return { x = m.x + tonumber(x), y = m.y + tonumber(y), w = tonumber(w), h = tonumber(h), g = tonumber(g),
                     bar = tonumber(bar) }
        end
    end
end
local function place_in_zone(win, m, zone)
    local b, bar = zone_box(m, zone), dots.titlebar_height and dots.titlebar_height(win) or 0
    place(win, { x = b.x, y = b.y + bar, w = b.w, h = b.h - bar })
    set_area(win, m)
end
-- A snapped window after its screen's size, the gaps or its title bar changed (old: the free part, the seam and the bar
-- it had): each of its edges on the screen's border kept there, each on a seam moved with the seam's middle in
-- proportion (so its neighbour's edge, across the same gap, moves the same: a resized pair keeps its split, not back to
-- halves), the new gap either side of that middle; its outer box (the bar's top down) the same, the bar as it is now
local function place_scaled(win, old, a, m)
    local o = { x = win.at.x, y = win.at.y - old.bar, w = win.size.x, h = win.size.y + old.bar }
    local g, h, bar = seam(), old.g / 2, bar_of(win)
    local function near(p, q) return math.abs(p - q) <= 3 end
    local function sx(v) return a.x + (v - old.x) * a.w / old.w end
    local function sy(v) return a.y + (v - old.y) * a.h / old.h end
    local l = near(o.x, old.x) and a.x or sx(o.x - h) + g / 2
    local r = near(o.x + o.w, old.x + old.w) and a.x + a.w or sx(o.x + o.w + h) - g / 2
    local t = near(o.y, old.y) and a.y or sy(o.y - h) + g / 2
    local b = near(o.y + o.h, old.y + old.h) and a.y + a.h or sy(o.y + o.h + h) - g / 2
    place(win, { x = l, y = t + bar, w = r - l, h = b - t - bar })
    set_area(win, m)
end
unsnap = function(win)
    local list = {}
    for _, t in ipairs(win.tags or {}) do list[#list + 1] = t end  -- (a copy: taking tags off may change the window's)
    for _, t in ipairs(list) do
        if t == "snapped" or t:match("^snap_") or t:match("^snaparea_") then
            hl.dispatch(hl.dsp.window.tag({ tag = "-" .. t, window = "address:" .. win.address }))
        end
    end
end
local function snapped_zone(win)
    for _, t in ipairs(win.tags or {}) do
        local z = t:match("^snap_(%a+)$")
        if z and zones[z] then return z end
    end
end

-- A window into a zone on screen m (before: its size to go back to, dragged away)
local function snap_into(win, m, zone, before)
    -- (on another screen than most of it is on: onto that screen's workspace too)
    local mws = m.active_workspace
    if mws and mws.id and win.workspace and mws.id ~= win.workspace.id then
        hl.dispatch(hl.dsp.window.move({ workspace = mws.id, follow = false, window = win }))
    end
    if zone == "max" then
        set_maximised(win, true)
        place(win, maximised_box(win, m))
    else
        if is_maximised(win) then set_maximised(win, false) end
        unsnap(win)
        hl.dispatch(hl.dsp.window.tag({ tag = "+snapped", window = "address:" .. win.address }))
        hl.dispatch(hl.dsp.window.tag({ tag = "+snap_" .. zone, window = "address:" .. win.address }))
        place_in_zone(win, m, zone)
    end
    snap_before[win.address] = before
    raise(win)
end

-- Snap Assist, as on Windows: a window snapped into a half, the other half empty (no window snapped into any of it on
-- that workspace), the switcher (~/.config/quickshell/switcher, its "assist" mode) shows the workspace's other windows
-- there: "agros_assist <screen> <the other half> <the snapped window> x y w h" (the half's box on the screen). The
-- one picked fills it (dots.snap_to); Esc or a click elsewhere leaves it empty
local opposite = { left = "right", right = "left", bottom = "top", top = "bottom" }
local function overlap(a, b)
    a, b = zones[a], zones[b]
    return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end
local function assist(win, m, zone)
    local other = opposite[zone]
    if not (other and win.workspace) then return end
    for _, w in ipairs(hl.get_windows() or {}) do
        local z = w.address ~= win.address and w.workspace and w.workspace.id == win.workspace.id and snapped_zone(w)
        if z and overlap(z, other) then return end
    end
    local b = zone_box(m, other)
    local x, y = px(b.x), px(b.y)
    tell(string.format("agros_assist %s %s %s %d %d %d %d", m.name, other, win.address, x - m.x, y - m.y,
        px(b.x + b.w) - x, px(b.y + b.h) - y))
end
-- The window Snap Assist picked (a minimised one back first), into that half of that screen
function dots.snap_to(address, zone, screen)
    local win = by_address(address)
    if not (win and zones[zone]) then return end
    local ws = win.workspace and tonumber((win.workspace.name or ""):match("^special:minimised%-(%d+)$"))
    if ws then
        restore(win, ws)
        win = by_address(address)
    end
    if not snappable(win) then return end
    local m
    for _, o in ipairs(hl.get_monitors() or {}) do if o.name == screen then m = o end end
    if not m then return end
    local before = snap_before[win.address]
    if not (before and (has_tag(win, "snapped") or is_maximised(win))) then before = { w = win.size.x, h = win.size.y } end
    snap_into(win, m, zone, before)
    hl.dispatch(hl.dsp.focus({ window = win }))
end

snap_drag_start = function(win, kind)
    tell("agros_drag 1")  -- (any drag: Caelestia's panels wait)
    if not snappable(win) then return nil end
    if kind == "move" then
        local before = snap_before[win.address]
        snap_before[win.address] = nil
        if not (has_tag(win, "snapped") or is_maximised(win)) then before = nil end
        if has_tag(win, "snapped") then
            before = before or standard_box(win)
            unsnap(win)
        end
        snap_zone, snap_screen, moving = nil, nil, true
        update_zone()
        return before
    end
    -- A resize of a snapped window: its snapped neighbours follow
    if has_tag(win, "snapped") then
        local with = neighbours(win)
        if #with > 0 then
            follow = { address = win.address, with = with }
            hl.animation({ leaf = "windowsMove", enabled = false })
        end
    end
    return nil
end

-- (every drag's end, also one whose start went unseen, or after a reload mid-drag: the preview and "dragging" end)
snap_drag_end = function(win, kind)
    local zone, screen = snap_zone, snap_screen
    moving, snap_zone, snap_screen = false, nil, nil
    tell("agros_drag 0")
    if zone or kind == "move" then tell("agros_snap none") end
    if follow then
        follow_step()
        follow = nil
        hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "standard" })  -- (animations.lua's)
    end
    if kind ~= "move" or not win then return end
    if not zone then return keep_reachable(win) end
    if not snappable(win) then return end
    local m
    for _, o in ipairs(hl.get_monitors() or {}) do if o.name == screen then m = o end end
    if not m then return keep_reachable(win) end
    snap_into(win, m, zone, { w = win.size.x, h = win.size.y })
    assist(by_address(win.address) or win, m, zone)
end
function dots.window_drag_step(_, kind)
    if kind == "move" and moving then update_zone() elseif follow then follow_step() end
end
function dots.window_drag_end(address, kind)
    local win = by_address(address)
    snap_drag_end(win, kind)
    -- A fullscreen game dragged to another screen (Super+drag): fullscreen on the screen it's dropped on. Left floating,
    -- Wine moved it itself to where that screen is in XWayland's layout, which isn't Hyprland's: off every screen
    if game_drags[address] and win and kind == "move" then
        local m = hl.get_monitor_at_cursor()
        local ws = m and m.active_workspace
        if ws and (ws.id or 0) > 0 and not (win.workspace and win.workspace.id == ws.id) then
            hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = win }))
        end
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set", window = win }))
    end
    game_drags[address] = nil
end

-- Always within reach --------------------------------------------------------------------------------------------------

-- As on Windows, a floating window can always be dragged again: its title bar (the plugin's, or the app's own at its
-- top) all below the screen's top border (Caelestia's), and at least 150 px of it (or all, if narrower) inside its left
-- and right borders and above the bottom one. Not on a side with another screen beyond (it may reach across). After
-- each move, and after a screen change (below)
keep_reachable = function(win)
    if not (win and win.floating and (win.fullscreen or 0) == 0 and win.workspace and (win.workspace.id or 0) > 0)
        or (dots.is_game and dots.is_game(win)) then return end
    -- (an X11 menu or tooltip, Caelestia's xwl_popup tag: placed by its app, by the pointer)
    for _, t in ipairs(win.tags or {}) do
        if t == "xwl_popup" or t == "xwl_popup*" then return end
    end
    local m = win.monitor or hl.get_active_monitor()
    if not m then return end
    local r, mw, mh = m.reserved, screen_size(m)
    local bar = dots.titlebar_height and dots.titlebar_height(win) or 0
    local fx, fy, fw, fh = m.x + r.left, m.y + r.top, mw - r.left - r.right, mh - r.top - r.bottom
    local function beyond(px, py) return screen_beyond(m, px, py) end
    -- (another screen beyond: looked for along the title bar's line, kept within this screen: the window's own y or
    -- middle may be off it)
    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    local keep, x, y = math.min(150, win.size.x), win.at.x, win.at.y
    local keep_down = math.min(150, win.size.y + bar)
    local ty = clamp(y - bar, m.y, m.y + mh - 1)
    if x + win.size.x < fx + keep and not beyond(m.x - 1, ty) then x = fx + keep - win.size.x end
    if x > fx + fw - keep and not beyond(m.x + mw, ty) then x = fx + fw - keep end
    local tx = clamp(x + win.size.x / 2, m.x, m.x + mw - 1)
    if y - bar < fy and not beyond(tx, m.y - 1) then y = fy + bar end
    if y - bar > fy + fh - keep_down and not beyond(tx, m.y + mh) then y = fy + fh - keep_down + bar end
    if x ~= win.at.x or y ~= win.at.y then
        hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), relative = false, window = win }))
    end
end

-- A screen's size changed (its resolution, a VM's window resized), or screens added or removed: every floating window
-- fits the screen it's on now, as tiled ones do. Maximised ones fill it again, snapped ones their zone, the rest are
-- kept within reach. Once per change (Hyprland's event), nothing watching in between
-- (a snapped window: from the free part it was placed for, on this screen, if that changed; moved with its workspace
-- to another screen, or with none recorded, into its zone there)
-- (one window: also as a minimised one comes back, the screens maybe changed while it was away)
function dots.refit_window(w)
    if not (w and w.floating and (w.fullscreen or 0) == 0 and w.workspace and (w.workspace.id or 0) > 0
        and not (dots.is_game and dots.is_game(w))) then return end
    local zone, m = snapped_zone(w), w.monitor
    local old = zone and m and recorded_area(w, m)
    local a = m and snap_area(m)
    if is_maximised(w) then
        local b = maximised_box(w)
        local x, y = px(b.x), px(b.y)
        if w.at.x ~= x or w.at.y ~= y or w.size.x ~= px(b.x + b.w) - x or w.size.y ~= px(b.y + b.h) - y then
            place(w, b)
        end
    elseif old and old.w > 0 and old.h > 0 then
        if old.w ~= math.floor(a.w) or old.h ~= math.floor(a.h) or old.x ~= math.floor(a.x) or old.y ~= math.floor(a.y)
            or old.g ~= math.floor(seam()) or old.bar ~= bar_of(w) then
            place_scaled(w, old, a, m)
        end
    elseif zone and m then place_in_zone(w, m, zone)
    else keep_reachable(w) end
end
function dots.refit_maximised()
    for _, w in ipairs(hl.get_windows() or {}) do dots.refit_window(w) end
end
hl.on("monitor.layout_changed", function() dots.refit_maximised() end)
-- ...and the maximised and snapped ones (no other: they're where they were put) after what can change their box: the
-- gaps or border (a config reload: the Settings app, Caelestia's Game mode off; a setting made while running: Game mode
-- on), title bars on or off, the reserved space (Caelestia's bar back after a restart). Hyprland's events for those
-- come for much else too (any setting or rule made, a workspace renamed; a layer, a notification, opened or closed):
-- each window placed only if its box changed, once things settle (a second after the last of a burst: the timer
-- started again by each; a reload with Game mode on puts its gaps back straight after, so nothing moves out and back).
-- Also called from Caelestia (the overlay's bar_space_refit): its bar's reserved space changes with no event here
local refit_timer = nil
local function refit_placed()
    refit_timer = nil
    for _, w in ipairs(hl.get_windows() or {}) do
        if is_maximised(w) or snapped_zone(w) then dots.refit_window(w) end
    end
end
function dots.refit_placed_soon()
    if refit_timer then return refit_timer:set_timeout(1000) end
    refit_timer = hl.timer(refit_placed, { timeout = 1000, type = "oneshot" })
end
hl.on("config.props_refreshed", dots.refit_placed_soon)
hl.on("layer.opened", dots.refit_placed_soon)
hl.on("layer.closed", dots.refit_placed_soon)

-- Floating and tiling -------------------------------------------------------------------------------------------------

-- The floating/tiling switch (the bar's right-click menu, Super+Alt+Space): every window on every workspace, minimised
-- ones included, floats or tiles, and new ones follow (below). Floating again, maximised windows stay maximised and
-- the rest cascade from the middle at the standard size
function dots.toggle_window_mode()
    local float = window_mode() == "tiling"
    local f = io.open(mode_file, "w")
    if f then
        f:write(float and "floating\n" or "tiling\n")
        f:close()
    end
    apply_mode_settings(float and "floating" or "tiling")
    -- Normal workspaces and the minimised windows' (special:minimised-N), not other special ones (Spotify's hidden one).
    -- Not games (dots.is_game, apps.lua: Proton, Lutris, gamescope, native): they always float at their own size (on_open below).
    -- Nor pinned windows (picture-in-picture, Capri), minimised ones too: on every workspace, tiling unpinned them for good
    local function switched(w)
        if w.pinned or has_tag(w, "minimised_pinned") or dots.is_game and dots.is_game(w) then return false end
        return w.workspace and ((w.workspace.id or 0) > 0 or (w.workspace.name or ""):match("^special:minimised%-"))
    end
    for _, w in ipairs(hl.get_windows() or {}) do
        -- A windowed game left tiled when going floating floats too, at its own size (not placed below): a tiled window
        -- on a workspace makes every new one there tile (on_open). Not a fullscreen one: left as it is
        local game_to_float = float and dots.is_game and dots.is_game(w) and (w.fullscreen or 0) == 0
            and w.workspace and ((w.workspace.id or 0) > 0 or (w.workspace.name or ""):match("^special:minimised%-"))
        if (switched(w) or game_to_float) and w.floating ~= float then
            hl.dispatch(hl.dsp.window.float({ action = float and "on" or "off", window = w }))
        end
    end
    if not float then return end
    for _, w in ipairs(hl.get_windows() or {}) do
        if switched(w) and w.floating then
            place_floating(w)
        end
    end
end

dots.bind("window_mode", function() dots.toggle_window_mode() end)

-- In floating mode a new window floats; in tiling mode too on a workspace whose windows all float (e.g. dialogs).
-- A workspace whose windows all tile stays tiled. (Tiled windows are always drawn under floating ones, so a new tiled
-- one among floating ones would be stuck behind them: Alt+Tab couldn't raise it.) It opens in the middle at the
-- standard size. One that opens maximised (an app restoring its last state, as VS Code does) is maximised as floating
-- windows are: Hyprland maximised it while still tiled, so it came out filling the screen with no room for its title bar.
-- Fullscreen windows are left as they are, and games (dots.is_game) keep their own size and place: most run borderless
-- over the whole screen, which would count as maximised and shrink them into the gaps
-- A window that opens floating (a popup, a dialog: Hyprland floats those itself) keeps its own size, in the middle;
-- only one bigger than the screen's free part is shrunk to it (a wide one went off the screen), and one opening off it
-- is brought within reach. Not games
local function fit_popup(win)
    if (win.fullscreen or 0) ~= 0 or not win.workspace or (win.workspace.id or 0) < 1
        or (dots.is_game and dots.is_game(win)) then return end
    local full = maximised_box(win)
    if win.size.x <= full.w and win.size.y <= full.h then return keep_reachable(win) end
    local w, h = math.min(win.size.x, full.w), math.min(win.size.y, full.h)
    place(win, { x = full.x + (full.w - w) / 2, y = full.y + (full.h - h) / 2, w = w, h = h })
end
-- A modal dialog floats, so it opens at its own size (fit_popup), never stretched and cascaded like a main window.
-- Hyprland floats a dialog that has a parent itself; one shown before its parent window has appeared has none (qView's
-- first-run Welcome came out at the standard size, behind the picture it was opened for). Its window objects don't
-- say modal: only a rule's match does
hl.window_rule({ match = { modal = true }, float = true })
-- The settings (Caelestia's Nexus, a Quickshell window that floats as it opens): a main window, at the standard size
-- and cascaded as one, not the size Nexus asks for (93% of the screen's height, nearly all of it)
local function is_settings(win)
    return win.class == "org.quickshell" and (win.title or ""):find("^Nexus") ~= nil
end
local function on_open(win, retried)
    if win and win.floating and not retried and is_settings(win) and (win.fullscreen or 0) == 0
        and win.workspace and (win.workspace.id or 0) >= 1 then
        return place(win, cascaded(win, standard_box(win)))
    end
    if win and win.floating and not retried then return fit_popup(win) end
    -- (fullscreen: 2, or 3 maximised and fullscreen, as focus_window's; 1 is only maximised)
    if not (win and win.workspace) or win.floating or (win.fullscreen or 0) >= 2 then return end
    -- At login a window can open before its workspace has an id: looked at again a moment later, by its address (it
    -- may have closed meanwhile). A sleep in its own process, not hl.timer: a config reload (likely at login, as the
    -- screens come up) would drop the timer, and the window, and every one opened next to it, would stay tiled
    -- (a special workspace never has one: nothing to wait for)
    if not win.workspace.id and not win.workspace.special then
        if retried then return end
        return hl.exec_cmd("sh -c 'sleep 0.2; exec hyprctl eval \"dots.open_retry([[" .. win.address .. "]])\"'")
    end
    if (win.workspace.id or 0) < 1 then return end
    local others = 0
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.address ~= win.address and w.workspace and w.workspace.id == win.workspace.id then
            if not w.floating then return end
            others = others + 1
        end
    end
    if others == 0 and window_mode() ~= "floating" then return end
    if dots.is_game and dots.is_game(win) then return hl.dispatch(hl.dsp.window.float({ action = "on", window = win })) end
    -- Maximised by the app's own wish only, not by its size: Hyprland has tiled it by now, the lone tiled window on its
    -- workspace, so its size is the layout's, not the app's; and that's the maximised box itself when Caelestia's gap
    -- round a window alone is no wider than the one at the screen's edges (the Settings app's Windows group), which
    -- opened every window maximised
    local maximised = win.fullscreen == 1
    if maximised then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    end
    hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
    -- Floating now (win is live), so its boxes leave room for the title bar
    if maximised then set_maximised(win, true) end
    place(win, maximised and maximised_box(win) or cascaded(win, standard_box(win)))
end
hl.on("window.open", function(win) on_open(win) end)

-- An app opened over a game that covers its screen (fullscreen, or borderless over it: from the launcher, the dock, a
-- link): the game minimised, as Alt+Tab does (focus_window), and the app shown, focused. Hyprland took the game out of
-- fullscreen for it (on_focus_under_fullscreen) and left it over the whole screen, the app behind it and the shell's
-- clicks going nowhere. Not for the game's own windows (a game, or started for one: its launcher, a dialog, its crash
-- reporter), X11 menus and toasts (Caelestia's xwl_popup), nor one on a special workspace (minimised, the splash's)
local function covers_screen(w)
    local m = w.monitor
    if not (m and m.width and m.scale and w.size and w.size.x) then return false end
    local mw, mh = screen_size(m)
    return w.size.x >= mw - 1 and w.size.y >= mh - 1
end
function dots.game_under(win)
    if not (win and win.workspace and (win.workspace.id or 0) >= 1) then return nil end
    if dots.is_game and dots.is_game(win) or dots.started_for_game and dots.started_for_game(win.pid) then return nil end
    for _, t in ipairs(win.tags or {}) do
        if t:find("^xwl_popup") then return nil end
    end
    for _, g in ipairs(hl.get_windows() or {}) do
        if g.address ~= win.address and g.workspace and g.workspace.id == win.workspace.id and dots.is_game
            and dots.is_game(g) and ((g.fullscreen or 0) >= 2 or covers_screen(g)) then
            return g
        end
    end
    return nil
end
-- Also an app already open, focused over the game (the dock, the bar, the Super menu bringing its window forward)
local function off_game(win, opened)
    if restoring then return end
    local game = dots.game_under(win)
    if not game then return end
    dots.window_fades(false)
    dots.minimise_window(game)
    if opened then hl.dispatch(hl.dsp.focus({ window = win })) end
    hl.exec_cmd("sh -c 'sleep 0.5; exec hyprctl eval \"dots.window_fades(true)\"'")
end
hl.on("window.open", function(win) off_game(win, true) end)
hl.on("window.active", function(win) off_game(win) end)

-- A game Hyprland took out of fullscreen as another window took the focus (on_focus_under_fullscreen): fullscreen again
-- as you go back to it (a click, Alt+Tab, the dock) while it still covers its screen. The game doesn't ask again
-- itself: it stayed a window over the whole screen with Caelestia's bar and borders drawn over it (Overwatch). One made
-- smaller (windowed in the game's own settings) stays as it is; a store launcher's windows aren't a game's
local out_of_fullscreen = {}
-- (gone with its window: Hyprland gives a closed window's address to a new one, which would be made fullscreen)
hl.on("window.close", function(win) if win then out_of_fullscreen[win.address] = nil end end)
hl.on("window.fullscreen", function(win)
    if win and (win.fullscreen or 0) == 0 and dots.is_game and dots.is_game(win) then out_of_fullscreen[win.address] = true end
end)
hl.on("window.active", function(win)
    if not (win and out_of_fullscreen[win.address]) then return end
    out_of_fullscreen[win.address] = nil
    if (win.fullscreen or 0) == 0 and win.workspace and (win.workspace.id or 0) > 0 and covers_screen(win) then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set", window = win }))
    end
end)
-- (and at a config load, the games over their screen out of fullscreen by then: a moment after, once apps.lua, loaded
-- after this file, has given dots.is_game)
function dots.games_out_of_fullscreen()
    for _, w in ipairs(hl.get_windows() or {}) do
        if (w.fullscreen or 0) == 0 and dots.is_game and dots.is_game(w) and covers_screen(w) then
            out_of_fullscreen[w.address] = true
        end
    end
end
if not dots.verifying then
    hl.exec_cmd("sh -c 'sleep 1; exec hyprctl eval \"dots.games_out_of_fullscreen()\"'")
end
function dots.open_retry(address) on_open(by_address(address), true) end

-- Window peek (the shell's WindowPeek.qml, resting on a preview in the dock or the workspace picker): only the windows
-- shown kept on their screen, every other window there faded out, as Hyprland draws them (title bar, border and all)
-- over the real desktop, widgets included. Nothing else changes (no focus, workspace or stacking).
-- - Faded by a tag whose rule makes a window see-through: Hyprland fades a window's opacity to a rule's value itself.
--   Taking the last such tag off, though, it jumps back at once: fading back, a window gets a tag whose rule gives it
--   the opacity it has without the peek, taken off once it's there (with no change then). That's Caelestia's for
--   every window (variables.lua's windowOpacity), but a fullscreen one's (none: the config's fullscreen_opacity) and
--   an opaque one's (drawn whole: opacity 1): Caelestia's opaque, game and xwl_popup tags, and apps.lua's dots_opaque
-- - Hyprland draws a window's blur at full strength whatever its opacity (decoration:blur:ignore_opacity), so the
--   blur stayed behind a window fading out until it was gone, then vanished: for the peek, the blur fades with its
--   window; the setting is put back after
-- - The rules are made at the first peek, not as this file loads: so they come after every rule of the config and win
--   over them, opaque = false over the opaque ones (which otherwise kept those windows in sight) (once per config
--   load: a reload drops them, and this file's state with them)
-- dots.peek_end() fades them back: the shell runs it when it starts too, so no window is left invisible by a shell
-- that crashed mid-peek
local peek = { gen = 0 }
local PEEK_BACK_MS = 3000 -- (long after Hyprland's fade: taking the tag off then changes nothing)
local PEEK_TAGS = { "dots-peek", "dots-peek-back", "dots-peek-back-see" }

local function peek_rules()
    if peek.rules then return end
    local ok, vars = pcall(require, "variables")
    local see = ok and type(vars) == "table" and tonumber(vars.windowOpacity) or 1
    local full = tonumber(hl.get_config("decoration.fullscreen_opacity")) or 1
    hl.window_rule({ name = "dots-peek", match = { tag = "dots-peek" }, opacity = "0 override", opaque = false })
    hl.window_rule({ name = "dots-peek-back", match = { tag = "dots-peek-back" }, opacity = "1 override", opaque = false })
    hl.window_rule({ name = "dots-peek-back-see", match = { tag = "dots-peek-back-see", fullscreen = false },
                     opacity = see .. " override", opaque = false })
    hl.window_rule({ name = "dots-peek-back-see-full", match = { tag = "dots-peek-back-see", fullscreen = true },
                     opacity = full .. " override", opaque = false })
    peek.rules = true
end

-- Drawn whole without the peek (the tags whose rules make a window opaque; a rule's tag has a "*")
local function opaque(w)
    for _, g in ipairs(w.tags or {}) do
        local t = g:gsub("%*$", "")
        if t == "opaque" or t == "game" or t == "xwl_popup" or t == "dots_opaque" then return true end
    end
    return false
end

local function retag(w, tag) hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = tag })) end

-- w with only that one of the peek's tags (none: nil). The new one put on before the old one's taken off: a rule's
-- opacity changing fades, the last one taken off doesn't
local function peek_tag(w, tag)
    if tag and not has_tag(w, tag) then retag(w, "+" .. tag) end
    for _, t in ipairs(PEEK_TAGS) do
        if t ~= tag and has_tag(w, t) then retag(w, "-" .. t) end
    end
end

-- The blur fading with its window (on), or as the config has it (off)
local function peek_blur(on)
    if on and peek.blur == nil then
        peek.blur = hl.get_config("decoration.blur.ignore_opacity") == true
        if peek.blur then hl.config({ decoration = { blur = { ignore_opacity = false } } }) end
    elseif not on and peek.blur ~= nil then
        if peek.blur then hl.config({ decoration = { blur = { ignore_opacity = true } } }) end
        peek.blur = nil
    end
end

-- peek_set(screen, keep): every window on that screen (its name) out of sight but those in keep (addresses), every
-- other window back; no screen: all back, and once faded back, nothing of the peek left
local function peek_set(screen, keep)
    -- (an end with nothing peeked, as the shell's start sends: nothing done, the blur setting not touched; but one whose
    -- peek faded nothing, every window kept, still sets the blur back)
    if screen == nil and peek.blur == nil then
        local any = false
        for _, w in ipairs(hl.get_windows() or {}) do
            for _, t in ipairs(w.tags or {}) do any = any or t:match("^dots%-peek") ~= nil end
        end
        if not any then return end
    end
    peek_rules()
    peek_blur(true)
    peek.gen = peek.gen + 1
    for _, w in ipairs(hl.get_windows() or {}) do
        if screen ~= nil and w.monitor ~= nil and w.monitor.name == screen and not keep[w.address] then
            peek_tag(w, "dots-peek")
        elseif has_tag(w, "dots-peek") then
            peek_tag(w, opaque(w) and "dots-peek-back" or "dots-peek-back-see")
        end
    end
    if screen then return end
    local gen = peek.gen
    hl.timer(function()
        if gen ~= peek.gen then return end
        for _, w in ipairs(hl.get_windows() or {}) do peek_tag(w, nil) end
        peek_blur(false)
    end, { timeout = PEEK_BACK_MS, type = "oneshot" })
end

function dots.peek_end() peek_set(nil, {}) end

-- dots.peek_screen(screen, address...): only those windows on that screen (none: the bare desktop, for the shell's
-- pictures of windows not on it); a screen that isn't there, the peek ends
function dots.peek_screen(screen, ...)
    local keep, found = {}, false
    for _, a in ipairs({ ... }) do keep[a] = true end
    for _, m in ipairs(hl.get_monitors() or {}) do found = found or m.name == screen end
    if not found then return dots.peek_end() end
    peek_set(screen, keep)
end
