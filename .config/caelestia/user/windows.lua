-- Windows, Windows-style: floating by default (a floating/tiling switch in the bar's right-click menu), opening in the
-- middle at one standard size, minimise and maximise (keys, the title bar buttons of titlebars.lua, apps' own), and
-- the clicked or picked window to the front.
-- Called from outside this file through hyprctl eval 'dots.<name>(...)': focus_window (Alt+Tab switcher, dock,
-- game-focus), focus_app (a click on a notification), minimise_window and maximise_window (title bar buttons),
-- toggle_window_mode (bar menu), refit_maximised (after a screen change), window_drag_start and titlebar_drag_start
-- (the title bar plugin, my patch to it: ~/.local/share/hyprbars/hyprbars.patch)
-- Caelestia's settings module (gaps, border): its defaults if an update renames it, not this whole file failing
local ok, vars = pcall(require, "variables")
if not ok or type(vars) ~= "table" then vars = {} end

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

-- A screen's size in the units windows are placed in: its mode over its scale, width and height swapped when it's
-- turned sideways (Hyprland gives the mode as it is, not turned)
local function screen_size(m)
    local w, h = m.width / m.scale, m.height / m.scale
    if (m.transform or 0) % 2 == 1 then return h, w end
    return w, h
end

-- Maximised: the screen inside the same gaps as tiled windows (the wallpaper still shows round it), with room for the
-- window's title bar (titlebars.lua, while the plugin is on)
local function maximised_box(win)
    local m = win.monitor or hl.get_active_monitor()
    local r, edge = m.reserved, (vars.windowGapsOut or 10) + (vars.windowBorderSize or 2)
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
local function place(win, box)
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(box.w), y = math.floor(box.h), window = win }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(box.x), y = math.floor(box.y), relative = false, window = win }))
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
-- Where a window goes when it starts floating (it opens, or a switch floats it): maximised windows (tagged) to the
-- maximised box, any other to the standard size, cascading
local function place_floating(win)
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
-- Focus on hover in floating mode too if chosen in the Settings app (windows.focus)
local function apply_mode_settings(mode)
    local floating = mode == "floating"
    local click = floating and dots.setting("windows.focus") ~= "hover"
    hl.config({ cursor = { no_warps = floating }, input = { follow_mouse = click and 2 or 1 } })
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

-- The window picked in the Alt+Tab switcher or the dock: focused and to the front. A minimised one comes back too
-- (the focus hook below)
-- switcher: picked with Alt+Tab, which minimises a fullscreen window you leave (a game), as on Windows; it comes back
-- fullscreen from the switcher, the dock or the restore key (Super+Alt+M)
-- Windows' fade in (Hyprland hides the rest of a workspace behind a fullscreen window, and fades it back in when that
-- one goes: the bare desktop showed first). Off while Alt+Tab leaves a fullscreen game, on again a moment later, as
-- animations.lua has it (the "fade" speed and curve)
function dots.window_fades(on)
    for _, leaf in ipairs({ "fadeIn", "fadeSwitch" }) do
        hl.animation({ leaf = leaf, enabled = on, speed = 6, bezier = "standard" })
    end
end

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
local function restore(win, ws)
    hl.dispatch(hl.dsp.window.move({ workspace = ws, window = win }))
    if has_tag(win, "minimised_pinned") then
        hl.dispatch(hl.dsp.window.tag({ tag = "-minimised_pinned", window = "address:" .. win.address }))
        hl.dispatch(hl.dsp.window.pin({ action = "on", window = win }))
    end
    hl.dispatch(hl.dsp.focus({ window = win }))
    raise(win)
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

-- A screen added or removed moves workspaces to other screens: maximised windows fit the screen they're on now (not
-- one bigger than it). After a moment, once the workspaces have moved; from a process of its own, as workspaces.lua
-- reloads the config on a screen change, which drops a timer here
function dots.refit_maximised()
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.floating and is_maximised(w) then place(w, maximised_box(w)) end
    end
end
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
function dots.window_drag_start(address, kind)
    local win = by_address(address)
    if not (win and win.floating and is_maximised(win)) then return end
    set_maximised(win, false)
    if kind ~= "move" then return end
    local box, cursor = standard_box(win), hl.get_cursor_pos()
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
local function on_open(win, retried)
    if not (win and win.workspace) or win.floating or win.fullscreen == 2 then return end
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
    local full = maximised_box(win)  -- still tiled here: the box without a title bar
    local maximised = win.fullscreen == 1 or (win.size.x >= full.w - 2 and win.size.y >= full.h - 2)
    if maximised and win.fullscreen == 1 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = win }))
    end
    hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
    -- Floating now (win is live), so its boxes leave room for the title bar
    if maximised then set_maximised(win, true) end
    place(win, maximised and maximised_box(win) or cascaded(win, standard_box(win)))
end
hl.on("window.open", function(win) on_open(win) end)
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

local function has_tag(w, tag)
    for _, g in ipairs(w.tags or {}) do if g == tag then return true end end
    return false
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
    peek_rules()
    peek_blur(true)
    peek.gen = peek.gen + 1
    for _, w in ipairs(hl.get_windows()) do
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
        for _, w in ipairs(hl.get_windows()) do peek_tag(w, nil) end
        peek_blur(false)
    end, { timeout = PEEK_BACK_MS, type = "oneshot" })
end

function dots.peek_end() peek_set(nil, {}) end

-- dots.peek(address): that window alone on its screen
function dots.peek(address)
    local win = by_address(address)
    if not win or not win.monitor then return dots.peek_end() end
    peek_set(win.monitor.name, { [win.address] = true })
end

-- dots.peek_screen(screen, address...): only those windows on that screen (none: the bare desktop, for the shell's
-- pictures of windows not on it); a screen that isn't there, the peek ends
function dots.peek_screen(screen, ...)
    local keep, found = {}, false
    for _, a in ipairs({ ... }) do keep[a] = true end
    for _, m in ipairs(hl.get_monitors() or {}) do found = found or m.name == screen end
    if not found then return dots.peek_end() end
    peek_set(screen, keep)
end
