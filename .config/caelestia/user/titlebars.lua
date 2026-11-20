-- Title bars with minimise / maximise / close buttons on floating windows only (tiled ones keep none), from the
-- hyprbars plugin with my patch (~/.local/share/hyprbars/hyprbars.patch: hover pills, restore icon, un-maximise on
-- drag, edge resizing, every window drag told to windows.lua (snapping, its seam cursor and press, the pointer kept
-- inside the screen's borders while moving)). Loaded last; an error here shows as a config error and the other files still load (Hyprland's require
-- catches it).
-- The plugin is loaded once Hyprland is up, by hyprbars-build --login, never from inside this config: loading it
-- reloads the config, and a reload in the middle of the config's own load took the whole desktop down. On that reload
-- hl.plugin.hyprbars exists and the settings below apply. --login builds the plugin first when it's missing or was
-- built for another Hyprland (in the background, with the AUR one, if installed, meanwhile)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/hyprbars-build --login") end)
if not hl.plugin.hyprbars then return end
-- Turned off in the Settings app: the plugin stays loaded (unloading it reloads the config), with no bar on any window
if dots.setting("windows.titlebars") == false then
    return hl.window_rule({ match = { class = ".*" }, ["hyprbars:no_bar"] = true })
end

-- In Caelestia's style: its colour scheme (follows the wallpaper: a scheme change reloads this), Rubik text and
-- Material Symbols Rounded icons like the shell, the windows' see-through blur, and the border wrapped round bar
-- and window as one shape (the bar's corners already follow the window rounding)
-- Caelestia's colours and settings modules: fixed dark colours if an update renames them, not this whole file failing
local function module(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or {}
end
local scheme, vars = module("scheme.current"), module("variables")
for k, v in pairs({ surfaceContainer = "1f1f25", onSurface = "e4e1e9", surfaceContainerHighest = "35343a",
                    error = "ffb4ab", onError = "690005" }) do scheme[k] = scheme[k] or v end
-- (from 0 to 1 whatever it is: a hand edit's 1.5 made three digits, a colour Hyprland can't read, and text that isn't
-- a number an error that stopped this file)
local alpha = string.format("%02x", math.floor(math.max(0, math.min(1, tonumber(vars.windowOpacity) or 1)) * 255))
-- This bar is the only set of window buttons: GTK apps (LibreWolf too, and any installed later) draw none, as the GTK
-- button layout has none (agros-welcome: window_buttons); VSCodium's are hidden (window.controlsStyle); Electron and Qt apps
-- draw none under Hyprland unless they draw their own title bar. Apps that can't hide theirs get no bar from here (a
-- second close button would be redundant), listed by class as Hyprland can't tell which those are: Steam, Proton VPN (its own minimise and close)
local own_title_bar = { "steam", "proton.vpn.app.gtk" }
local height = 32
-- dots.titlebar_height: windows.lua's maximise leaves room for the bar above a window that has one. None exactly where
-- the rules at the end give none, by the same tags and classes: fullscreen windows, Caelestia's game tag (games; a
-- store launcher, which under Proton or Lutris gets it too with the class steam_app_default, has its bar, tagged
-- store_launcher by apps.lua), Proton's steam_app_<id>, X11 menus and pop-ups (Caelestia's xwl_popup tag), apps with
-- their own
function dots.titlebar_height(win)
    if not win.floating or win.fullscreen ~= 0 or (win.class or ""):match("^steam_app_%d+$") then return 0 end
    local tags = {}
    for _, t in ipairs(win.tags or {}) do tags[t:gsub("%*$", "")] = true end
    if tags.xwl_popup or tags.game and not tags.store_launcher then return 0 end
    for _, c in ipairs(own_title_bar) do
        if win.class == c then return 0 end
    end
    return height
end
hl.config({ plugin = { hyprbars = {
    bar_height                 = height,
    bar_color                  = "rgba(" .. scheme.surfaceContainer .. alpha .. ")",
    bar_blur                   = true,
    ["col.text"]               = "rgb(" .. scheme.onSurface .. ")",
    -- Icons are drawn in the same font as the title: Rubik has no Material Symbols codepoints, so they fall through
    bar_text_font              = "Rubik, Material Symbols Rounded",
    bar_text_size              = 11,
    bar_text_weight            = "medium",
    bar_text_align             = "left",
    -- Buttons: squares the bar's height, side by side, flush with the right edge (my patch gives the title its own gap)
    bar_padding                = 0,
    bar_button_padding         = 0,
    bar_precedence_over_border = true,
    inactive_button_color      = "rgb(" .. scheme.surfaceContainerHighest .. ")",
    -- {address}: the bar's own window (dots.bar_window, below)
    on_double_click            = "hyprctl eval 'local w = dots.bar_window(\"{address}\") if w then dots.maximise_window(w) end'",
} } })
-- Right to left: close, maximise, minimise (as on Windows); maximise and minimise are windows.lua's Super+Alt+F, Super+M.
-- 40 px wide (size), the bar's full height, no gaps. Icons by Material Symbols codepoint: close, crop_square, remove; on
-- a maximised window (tagged so by windows.lua) the maximise button shows filter_none, two stacked squares, for
-- "restore" (icon_maximised: my patch to the plugin)
-- No backgrounds: the button under the mouse gets a rounded rectangle (my patch), a faint white, or for close the red of
-- Caelestia's power button (error) with a dark icon on it (hover_color, hover_fg_color: my patch). Minimise and close
-- icons a little bigger than maximise's (icon_size: my patch; their glyphs look smaller at one size)
local none = "rgba(00000000)"
-- The window a bar's button or double click is for: {address}, its own (the patched plugin fills it in), not whichever
-- has focus by the time the command runs; the focused one with the AUR plugin, which leaves "{address}" as it is. None
-- when it's gone by then: a second click on close as a slow app (LibreWolf, VSCodium) shut closed the window that had
-- the focus next
function dots.bar_window(address)
    if address:find("{", 1, true) then return hl.get_active_window() end
    return hl.get_window("address:" .. address)
end
local function button(icon, action, opts)
    hl.plugin.hyprbars.add_button({ bg_color = none, fg_color = "rgb(" .. scheme.onSurface .. ")", size = 40,
                                    icon = utf8.char(icon), icon_maximised = opts.maximised and utf8.char(opts.maximised),
                                    hover_color = opts.hover, hover_fg_color = opts.hover_fg, icon_size = opts.icon_size,
                                    action = action })
end
local function on_bar(code) return "hyprctl eval 'local w = dots.bar_window(\"{address}\") if w then " .. code .. " end'" end
-- Whether a process is a Windows program run by Wine (Proton's too): its executable is Wine's loader
local function wine_program(pid)
    local p = io.popen("readlink /proc/" .. math.floor(pid) .. "/exe 2>/dev/null")
    local exe = p and p:read("l") or ""
    if p then p:close() end
    return exe:find("/wine[^/]*$") ~= nil
end
-- Close, from the bar: the window asked to close, as always. A Wine program's still there a moment later, with no new
-- window of its own since (a "save changes?": Wine's dialogs are windows of their own), is ended: store launchers under
-- Proton (Epic's) ignore the request (and Alt+F4) and close only from their own X. Other apps aren't: one may ask
-- "save?" inside its own window, which can't be told from ignoring it
function dots.close_window(w)
    local address, pid = w.address, w.pid
    local before = {}
    for _, o in ipairs(hl.get_windows() or {}) do before[o.address] = true end
    hl.dispatch(hl.dsp.window.close({ window = w }))
    if not pid or pid <= 0 or not wine_program(pid) then return end
    hl.timer(function()
        local still = hl.get_window("address:" .. address)
        if not still or still.mapped == false then return end
        for _, o in ipairs(hl.get_windows() or {}) do
            if o.pid == pid and not before[o.address] then return end
        end
        hl.exec_cmd("kill " .. math.floor(pid))
    end, { timeout = 1500, type = "oneshot" })
end
button(0xe5cd, on_bar("dots.close_window(w)"),
       { hover = "rgb(" .. scheme.error .. ")", hover_fg = "rgb(" .. scheme.onError .. ")", icon_size = 16 })
button(0xe3c6, on_bar("dots.maximise_window(w)"), { maximised = 0xe3e0 })
button(0xe15b, on_bar("dots.minimise_window(w)"), { icon_size = 16 })
hl.window_rule({ match = { float = false }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { fullscreen = true }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { class = "^steam_app_\\d+$" }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { tag = "game" }, ["hyprbars:no_bar"] = true })  -- Lutris, gamescope, native Steam games too
-- A store launcher's window has its bar (floating, not fullscreen: the rules above still apply): the game tag above came
-- with its class (apps.lua tags it store_launcher)
hl.window_rule({ match = { tag = "store_launcher", float = true, fullscreen = false }, ["hyprbars:no_bar"] = false })
-- XWayland popups (Caelestia's xwl_popup tag: menus and pop-ups of X11 apps, Wine's included) float, but aren't windows
hl.window_rule({ match = { tag = "xwl_popup" }, ["hyprbars:no_bar"] = true })
local classes = {}
for i, c in ipairs(own_title_bar) do classes[i] = c:gsub("%.", "\\.") end
hl.window_rule({ match = { class = "^(" .. table.concat(classes, "|") .. ")$" }, ["hyprbars:no_bar"] = true })
