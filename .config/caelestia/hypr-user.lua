-- Personal Hyprland settings, loaded after Caelestia's (~/.config/hypr is Caelestia's: never edit it; its variables,
-- keys included, are changed in hypr-vars.lua). The rest is split by topic in ~/.config/caelestia/user/.

-- Keyboard layout: the system's (localectl set-x11-keymap, the setup's keyboard step), as the login screen and
-- scroll-lock read it too
local kb = io.open("/etc/X11/xorg.conf.d/00-keyboard.conf")
if kb then
    local conf = kb:read("a")
    kb:close()
    local input = {}
    for key, opt in pairs({ kb_layout = "XkbLayout", kb_variant = "XkbVariant", kb_options = "XkbOptions" }) do
        input[key] = conf:match('"' .. opt .. '"%s+"([^"]*)"')
    end
    if input.kb_layout then hl.config({ input = input }) end
end
-- The mouse pointer drawn as part of the picture, not on the graphics card's separate cursor layer: nothing clears
-- that layer when the desktop closes, so the pointer stayed on the shutdown screen
hl.config({ cursor = { no_hardware_cursors = 1 } })
-- No "Hyprland updated" news window after an update
hl.config({ ecosystem = { no_update_news = true } })

-- The functions other programs call through hyprctl eval 'dots.<name>(...)' (the dock, the switcher, game-focus...),
-- kept in one table instead of loose globals; the README lists them ("Lua API")
dots = {}

-- Only a check (hypr-config-check: Hyprland --verify-config): loaded, nothing done on the side. No "failed to load"
-- notification (dotfiles-check gives its own) and no settings file written
local verify = os.getenv("DOTS_VERIFY_CONFIG") == "1"

-- Settings from the Settings app (~/.local/bin/dots-settings writes them here, every value, defaults included):
-- dots.setting("windows.cascade"). Written again first if missing or older than the list of settings (an update)
local settings_file = os.getenv("HOME") .. "/.config/dots/settings.lua"
local stale = io.popen("test -s '" .. settings_file .. "' -a '" .. settings_file
                       .. "' -nt ~/.local/share/dots-settings/schema.json || echo stale")
if stale then
    if stale:read("l") == "stale" and not verify then os.execute("~/.local/bin/dots-settings lua") end
    stale:close()
end
local ok, settings = pcall(dofile, settings_file)
local values = ok and type(settings) == "table" and settings or {}
-- Without it every setting is off and the shortcuts below have no keys (Alt+Tab included): say so, once the desktop
-- is up to show it (at login this runs before Caelestia, with no notification daemon yet)
if not (ok and type(settings) == "table") and not verify then
    hl.exec_cmd("sh -c 'sleep 15; exec notify-send -u critical -a Dotfiles -i dialog-warning"
                .. " \"Desktop settings failed to load\" \"Shortcuts like Alt+Tab and the apps started at login are off."
                .. " Run dots-settings lua in a terminal to see why.\"'")
end
function dots.setting(key) return values[key] end
-- My binds, by name: their keys are settings too (Settings app, Keyboard page; keys.<name>, defaults in its schema), a
-- list of none, one or more. Returns the binds made (to turn them off and on: set_enabled)
function dots.bind(name, action, opts)
    local made = {}
    for _, keys in ipairs(values["keys." .. name] or {}) do made[#made + 1] = hl.bind(keys, action, opts) end
    return made
end

-- No mouse acceleration by default: the pointer moves exactly as far as the hand ("flat"; games under XWayland get the
-- accelerated movement otherwise). On in the Settings app: libinput's default for mice ("adaptive")
if dots.setting("input.mouse_accel") ~= true then hl.config({ input = { accel_profile = "flat" } }) end

-- Each on its own: one that errors (a Hyprland update renamed something it uses) loses only itself, not the ones after
-- it, and says so (a notification once the desktop is up; hyprctl configerrors has the rest)
local function load(name)
    local ok, err = pcall(require, name)
    if ok then return end
    if not verify then
        hl.exec_cmd("sh -c 'sleep 15; exec notify-send -u critical -a Dotfiles -i dialog-warning"
                    .. " \"Part of the desktop config failed to load\" \"" .. name .. ": see hyprctl configerrors\"'")
    end
    error(name .. ": " .. tostring(err), 0)  -- (after the rest has loaded: below)
end
local failed = {}
for _, name in ipairs({
    "user.monitors",    -- screen layout and refresh rates
    "user.workspaces",  -- workspaces synced across screens (Super+N)
    "user.keys",        -- Super+Tab / Alt+Tab switchers, Scroll Lock, my binds
    "user.windows",     -- floating by default, minimise / maximise, the clicked window to the front
    "user.apps",        -- Lutris, games, Spotify, Proton VPN, Solaar: rules and login starts
    "user.desktop",     -- widgets, login screen, keyring, Bluetooth, update and health checks
    "user.titlebars",   -- title bars on floating windows (a plugin; off unless it's installed)
}) do
    local ok, err = pcall(load, name)
    if not ok then failed[#failed + 1] = err end
end
-- still an error for Hyprland to show (configerrors, its banner), once everything that could load has
if #failed > 0 then error(table.concat(failed, "\n"), 0) end
