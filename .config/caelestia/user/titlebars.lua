-- Title bars with minimise / maximise / close buttons on floating windows only (tiled ones keep none), from the
-- hyprbars plugin with my patch (~/.local/share/hyprbars/hyprbars.patch: hover pills, restore icon, un-maximise on
-- drag). Loaded last; an error here shows as a config error and the other files still load (Hyprland's require
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
local alpha = string.format("%02x", math.floor((vars.windowOpacity or 1) * 255))
-- This bar is the only set of window buttons: GTK apps (LibreWolf too, and any installed later) draw none, as the GTK
-- button layout has none (agros-welcome: window_buttons); VSCodium's are hidden (window.controlsStyle); Electron and Qt apps
-- draw none under Hyprland unless they draw their own title bar. Apps that can't hide theirs get no bar from here (a
-- second close button would be redundant), listed by class as Hyprland can't tell which those are: Steam, Proton VPN (its own minimise and close)
local own_title_bar = { "steam", "protonvpn-app" }
local height = 32
-- dots.titlebar_height: windows.lua's maximise leaves room for the bar above a window that has one. None on fullscreen windows or
-- games (dots.is_game, apps.lua: often borderless over the whole screen, not fullscreen), as in the rules at the end
function dots.titlebar_height(win)
    if not win.floating or win.fullscreen ~= 0 or (dots.is_game and dots.is_game(win)) then return 0 end
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
    -- {address}: the bar's own window (the patched plugin fills it in), not whichever has focus by the time this runs;
    -- the focused one with the AUR plugin, which leaves it as it is
    on_double_click            = "hyprctl eval 'dots.maximise_window(hl.get_window(\"address:{address}\"))'",
} } })
-- Right to left: close, maximise, minimise (as on Windows); maximise and minimise are windows.lua's Super+Alt+F, Super+M.
-- 40 px wide (size), the bar's full height, no gaps. Icons by Material Symbols codepoint: close, crop_square, remove; on
-- a maximised window (tagged so by windows.lua) the maximise button shows filter_none, two stacked squares, for
-- "restore" (icon_maximised: my patch to the plugin)
-- No backgrounds: the button under the mouse gets a rounded rectangle (my patch), a faint white, or for close the red of
-- Caelestia's power button (error) with a dark icon on it (hover_color, hover_fg_color: my patch). Minimise and close
-- icons a little bigger than maximise's (icon_size: my patch; their glyphs look smaller at one size)
local none = "rgba(00000000)"
local function button(icon, action, opts)
    hl.plugin.hyprbars.add_button({ bg_color = none, fg_color = "rgb(" .. scheme.onSurface .. ")", size = 40,
                                    icon = utf8.char(icon), icon_maximised = opts.maximised and utf8.char(opts.maximised),
                                    hover_color = opts.hover, hover_fg_color = opts.hover_fg, icon_size = opts.icon_size,
                                    action = action })
end
button(0xe5cd, "hyprctl eval 'hl.dispatch(hl.dsp.window.close({ window = hl.get_window(\"address:{address}\") or hl.get_active_window() }))'",
       { hover = "rgb(" .. scheme.error .. ")", hover_fg = "rgb(" .. scheme.onError .. ")", icon_size = 16 })
button(0xe3c6, "hyprctl eval 'dots.maximise_window(hl.get_window(\"address:{address}\"))'", { maximised = 0xe3e0 })
button(0xe15b, "hyprctl eval 'dots.minimise_window(hl.get_window(\"address:{address}\"))'", { icon_size = 16 })
hl.window_rule({ match = { float = false }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { fullscreen = true }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { class = "^steam_app_\\d+$" }, ["hyprbars:no_bar"] = true })
hl.window_rule({ match = { tag = "game" }, ["hyprbars:no_bar"] = true })  -- Lutris, gamescope, native Steam games too
-- XWayland popups (Caelestia's xwl_popup tag: menus and pop-ups of X11 apps, Wine's included) float, but aren't windows
hl.window_rule({ match = { tag = "xwl_popup" }, ["hyprbars:no_bar"] = true })
local classes = {}
for i, c in ipairs(own_title_bar) do classes[i] = c:gsub("%.", "\\.") end
hl.window_rule({ match = { class = "^(" .. table.concat(classes, "|") .. ")$" }, ["hyprbars:no_bar"] = true })
