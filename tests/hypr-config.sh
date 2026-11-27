#!/usr/bin/env bash
# The Hyprland config (hypr-vars.lua, hypr-user.lua and user/*.lua) run by plain Lua against a stand-in for Hyprland's
# hl API, in a throwaway home: every file compiles; the whole config loads with the settings file missing, broken or
# odd, with and without the title bar plugin; the event handlers (windows opening, keys, screens) and the functions
# scripts call don't error; every dots.bind / dots.setting name is in the Settings app's schema and every function in
# the Lua API table (docs/how-it-works.md) exists
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# (the config's look at /sys, as on a machine with no NVIDIA driver loaded: never this machine's; a test sets its own)
mkdir -p "$t/sys-none"
export SYSFS=$t/sys-none
command -v lua >/dev/null || { echo "skip hypr-config (no lua)"; exit 0; }

for f in "$here"/.config/caelestia/*.lua "$here"/.config/caelestia/user/*.lua "$here"/.config/caelestia/user/hosts/*.lua; do
    out=$(F=$f lua -e 'assert(loadfile(os.getenv("F")))' 2>&1) || fail "doesn't compile: $out"
done

# Every setting the Lua reads is one the Settings app has (else it's silently nil: a bind with no keys, a switch that
# does nothing)
schema=$here/.local/share/dots-settings/schema.json
for k in $(cd "$here/.config/caelestia" && grep -rhoE 'dots\.bind\("[a-z_]+"' . | sed 's/.*("/keys./; s/"$//') \
         $(cd "$here/.config/caelestia" && grep -rhoE 'dots\.setting\("[a-z_.]+"\)' . | sed 's/.*("//; s/")$//') \
         $(cd "$here/.config/caelestia" && grep -rhoE 'at_login\("[a-z]+"' . | sed 's/.*("/startup./; s/"$//'); do
    grep -q "\"key\": \"$k\"" "$schema" || fail "$k is read by the config but isn't in the Settings app's schema"
done

# Caelestia's own modules the config reads (its variables and colour scheme), as small as they come
mkdir -p "$t/home/.config/hypr/scheme" "$t/home/.config/dots" "$t/home/.local/state" "$t/home/.local/bin"
cp -r "$here/.config/caelestia" "$t/home/.config/"
cat >"$t/home/.config/hypr/variables.lua" <<'L'
return { kbGoToWs = "SUPER", gestureFingers = 3, windowGapsOut = 10, windowBorderSize = 1, windowOpacity = 0.95,
         kbMoveWinToWs = "SUPER + ALT", kbMoveWinToWsSilent = "SUPER + SHIFT", kbGoToWsGroup = "CTRL + SUPER",
         kbNextWs = { "SUPER + mouse_down", "CTRL + SUPER + Right" }, kbPrevWs = { "SUPER + mouse_up", "CTRL + SUPER + Left" },
         kbNextWsGroup = "CTRL + SUPER + mouse_down", kbMoveWinToWsNext = { "SUPER + ALT + Page_Down" } }
L
echo 'return { surfaceContainer = "1f1f25" }' >"$t/home/.config/hypr/scheme/current.lua"
# (no dots-settings or scroll-lock in this home: what hypr-user.lua runs of them finds nothing)

cat >"$t/stub.lua" <<'L'
-- Hyprland's hl, enough for the config: rules, binds and handlers recorded, queries answered from WINDOWS and SCREENS.
-- A bad argument is a config error (listed), not a Lua error, as in Hyprland. Focus and window moves are played on
-- SCREENS (FOCUS: the focused one's index) and WINDOWS (ACTIVE: the active window), what the binds do in BIND_ACTIONS;
-- LID: what /proc says of the laptop lid; RELOADED: a dispatched hypr-reload; SCREENS_RELOAD: the command a screen
-- change ran (its reload, then screens_changed)
local plugin = os.getenv("PLUGIN") == "1"
handlers, binds, config_errors, hidden_rules, unset_gestures, WINDOW_RULES = {}, {}, {}, {}, {}, {}
-- CONFIG: what hl.get_config answers (the blur setting window peek turns off and back); HELD_TIMERS: timers queued
-- there while HOLD_TIMERS is on (else run at once); PEEK_TAGS: window peek's tag dispatches, in order
CONFIG, HELD_TIMERS, PEEK_TAGS, TIMER_SETS = { ["decoration.blur.ignore_opacity"] = true }, {}, {}, {}
BIND_ACTIONS, MONITOR_RULES, FOCUS, ENV = {}, {}, 1, {}
-- SESSION_ENV: what was put in the user's systemd and D-Bus environments (never the real ones: a test run in a VMware VM
-- changed its session's)
SESSION_ENV = {}
local execute = os.execute
os.execute = function(cmd, ...)
    if cmd and cmd:find("set-environment", 1, true) then SESSION_ENV[#SESSION_ENV + 1] = cmd; return true end
    return execute(cmd, ...)
end
local popen = io.popen
io.popen = function(cmd, ...)
    if cmd:find("/proc/acpi/button/lid", 1, true) then return { read = function() return LID or "" end, close = function() end } end
    return popen(cmd, ...)
end
local function check(ok, msg) if not ok then config_errors[#config_errors + 1] = msg end end
SCREENS = { { id = 0, name = "DP-1", description = "Some Screen", x = 0, y = 0, width = 1920, height = 1080, scale = 1,
              transform = 0, reserved = { top = 40, bottom = 0, left = 0, right = 0 } },
            { id = 1, name = "HDMI-A-1", description = "Other Screen", x = 1920, y = 0, width = 2560, height = 1440,
              scale = 1.25, transform = 1, reserved = { top = 0, bottom = 0, left = 0, right = 0 } } }
function ws(id, name) return { id = id, name = name or tostring(id) } end
for k, m in ipairs(SCREENS) do m.active_workspace = ws((k - 1) * 10 + 1) end
WINDOWS = {
    { address = "0x1", class = "foot", title = "foot", floating = false, fullscreen = 0, pid = 1, tags = {},
      workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 900, y = 500 }, focus_history_id = 1 },
    { address = "0x2", class = "steam_app_1", title = "Game", floating = true, fullscreen = 2, pid = 1, tags = { "game*" },
      workspace = ws(2), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 1920, y = 1080 }, focus_history_id = 0 },
    { address = "0x3", class = "thunar", title = "Files", floating = true, fullscreen = 0, pid = 1, tags = { "maximised" },
      workspace = { name = "special:minimised-11", special = true }, monitor = SCREENS[2], at = { x = 10, y = 10 },
      size = { x = 800, y = 600 }, focus_history_id = 2 },
    -- (at login: no workspace id yet)
    { address = "0x4", class = "", title = "", floating = false, fullscreen = 0, pid = 1, tags = {},
      workspace = { name = "4" }, monitor = SCREENS[2], at = { x = 0, y = 0 }, size = { x = 1, y = 1 }, focus_history_id = 3 },
    -- (a special workspace: no id there since 0.57, nothing to wait for)
    { address = "0x5", class = "spotify", title = "Spotify", floating = false, fullscreen = 0, pid = 1, tags = {},
      workspace = { name = "special:hidden", special = true }, monitor = SCREENS[1], at = { x = 0, y = 0 },
      size = { x = 1, y = 1 }, focus_history_id = 4 },
}
-- ONE_SCREEN: a lone HiDPI laptop panel, every window on it (no second screen to fold workspaces onto)
if os.getenv("ONE_SCREEN") == "1" then
    SCREENS = { { id = 0, name = "eDP-1", description = "Unknown Panel", x = 0, y = 0, width = 2560, height = 1600,
                  scale = 1.6, transform = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 }, active_workspace = ws(1) } }
    for _, w in ipairs(WINDOWS) do w.monitor = SCREENS[1] end
end
local function rule() return { set_enabled = function() end, is_enabled = function() return true end } end
local dsp = setmetatable({}, { __index = function(t, k)
    local f = setmetatable({}, { __index = function(_, k2) return function(a) return { k .. "." .. k2, a } end end,
                                 __call = function(_, a) return { k, a } end })
    rawset(t, k, f)
    return f
end })
hl = {
    config = function(c)
        check(type(c) == "table", "hl.config: not a table")
        -- (every setting's path written down, those in handlers too: checked against Hyprland's own list at the end)
        local function record(tbl, prefix)
            for k, v in pairs(tbl) do
                local path = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
                if type(v) == "table" and #v == 0 then record(v, path) else
                    local f = io.open("config-keys", "a")
                    if f then f:write(path, "\n"); f:close() end
                end
            end
        end
        if type(c) == "table" then record(c) end
        if type(c) == "table" and type(c.cursor) == "table" and c.cursor.no_hardware_cursors ~= nil then
            HW_CURSORS = c.cursor.no_hardware_cursors
        end
        local blur = type(c) == "table" and c.decoration and c.decoration.blur
        if blur and blur.ignore_opacity ~= nil then CONFIG["decoration.blur.ignore_opacity"] = blur.ignore_opacity end
        local bars = type(c) == "table" and type(c.plugin) == "table" and c.plugin.hyprbars
        if bars and bars.bar_color then BAR_COLOR = bars.bar_color end
    end,
    get_config = function(key) return CONFIG[key] end,
    get_current_submap = function() return "" end,
    bind = function(keys, action)
        check(type(keys) == "string" and keys:match("%S"), "hl.bind: no keys: " .. tostring(keys))
        check(action ~= nil, "hl.bind: no action for " .. tostring(keys))
        binds[#binds + 1] = keys
        BIND_ACTIONS[keys] = BIND_ACTIONS[keys] or {}
        table.insert(BIND_ACTIONS[keys], action)
    end,
    unbind = function(keys) BIND_ACTIONS[keys] = nil end,
    gesture = function(g)
        if g.action == "unset" then unset_gestures[#unset_gestures + 1] = g.fingers .. " " .. g.direction end
    end,
    on = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
    exec_cmd = function(cmd)
        check(type(cmd) == "string", "hl.exec_cmd: not a string")
        if tostring(cmd):find("dots-warn", 1, true) then io.write("exec dots-warn\n") end
        if tostring(cmd):find("hypr-screens.lock", 1, true) then SCREENS_RELOAD = cmd end
        check(not cmd:find("open_retry([[0x5]]", 1, true), "a window on a special workspace waited for a workspace id")
    end,
    dispatch = function(d)
        check(d ~= nil, "hl.dispatch: nothing")
        local name, a = d and d[1], d and d[2] or {}
        if name == "focus" and a.monitor then
            for k, m in ipairs(SCREENS) do if m.name == a.monitor then FOCUS = k end end
        elseif name == "focus" and tonumber(a.workspace) then
            -- (a numbered workspace shows on the screen its rule names: the one for its 10, with two or more)
            local id = tonumber(a.workspace)
            local k = (a.on_current_monitor or #SCREENS < 2) and FOCUS or math.floor((id - 1) / 10) + 1
            if SCREENS[k] then SCREENS[k].active_workspace = ws(id); FOCUS = k end
        elseif name == "window.move" then
            local w = a.window or hl.get_active_window()
            if type(w) == "string" then w = hl.get_window(w) end
            local id = tonumber(a.workspace)
            -- (a move to a place, x and y, leaves its workspace)
            if w and a.workspace ~= nil then w.workspace = id and ws(id) or { name = a.workspace, special = true } end
            -- (followed unless follow = false: the window's workspace shown)
            if w and id and a.follow ~= false then hl.dispatch(hl.dsp.focus({ workspace = id })) end
        elseif name == "workspace.move" then
            -- (a screen's shown workspace moved away: it shows its own first one)
            for k, m in ipairs(SCREENS) do
                if m.name == a.monitor then m.active_workspace = ws(a.workspace)
                elseif m.active_workspace and m.active_workspace.id == a.workspace then m.active_workspace = ws((k - 1) * 10 + 1) end
            end
        elseif name == "window.tag" then
            -- (tags added, "+name", or taken off, "-name", as Hyprland's tag dispatcher: window peek's and snapping's; the
            -- maximised tag only recorded, as the drag tests set it themselves)
            local w = type(a.window) == "string" and hl.get_window(a.window) or a.window
            local sign, tag = tostring(a.tag):match("^([+-])(.+)$")
            if w and tag and (tag:match("^dots%-peek") or tag:match("^snap")) then
                if tag:match("^dots%-peek") then PEEK_TAGS[#PEEK_TAGS + 1] = w.address .. sign .. tag end
                w.tags = w.tags or {}
                for k = #w.tags, 1, -1 do if w.tags[k] == tag then table.remove(w.tags, k) end end
                if sign == "+" then w.tags[#w.tags + 1] = tag end
            end
        elseif name == "exec_cmd" and tostring(a):find("hypr-reload", 1, true) then
            RELOADED = true
        end
    end,
    -- (a held one's timeout, and each time it's set again, noted: TIMER_SETS)
    timer = function(fn, opts)
        if not HOLD_TIMERS then return fn() end
        HELD_TIMERS[#HELD_TIMERS + 1] = fn
        TIMER_SETS[#TIMER_SETS + 1] = opts and opts.timeout
        return { set_timeout = function(_, ms) TIMER_SETS[#TIMER_SETS + 1] = ms end }
    end,
    window_rule = function(r)
        check(type(r.match) == "table", "hl.window_rule: no match")
        -- Caelestia's tags with effects (its rules.lua) come before this config: tagged from here, they never apply
        local tag = tostring(r.tag or ""):match("^%+(.+)$")
        check(not (tag and (tag == "opaque" or tag:match("^float"))), "a window tagged " .. tostring(tag) .. " after Caelestia's rule for it")
        if tostring(r.workspace):match("^special:hidden") then hidden_rules[#hidden_rules + 1] = tostring(r.match.tag) end
        WINDOW_RULES[#WINDOW_RULES + 1] = r
        return rule()
    end,
    layer_rule = function() return rule() end,
    workspace_rule = function(r) check(type(r.workspace) == "string", "hl.workspace_rule: workspace not a string"); return rule() end,
    monitor = function(r) check(type(r.output) == "string", "hl.monitor: no output"); MONITOR_RULES[#MONITOR_RULES + 1] = r end,
    define_submap = function(_, fn) if type(fn) == "function" then fn() end end,
    -- (as Hyprland 0.57's: a screen that's off (enabled = false) listed only with { all = true })
    get_monitors = function(o)
        local list = {}
        for _, m in ipairs(SCREENS) do if o and o.all or m.enabled ~= false then list[#list + 1] = m end end
        return list
    end,
    get_active_monitor = function() return SCREENS[FOCUS] or SCREENS[1] end,
    get_active_workspace = function() return (SCREENS[FOCUS] or SCREENS[1]).active_workspace end,
    get_active_window = function() return ACTIVE or WINDOWS[os.getenv("GAME_FOCUSED") and 2 or 1] end,
    get_workspace = function(id)
        for _, m in ipairs(SCREENS) do
            if m.active_workspace and m.active_workspace.id == id then return { id = id, monitor = m } end
        end
    end,
    get_workspaces = function()
        local list = {}
        for _, m in ipairs(SCREENS) do
            if m.active_workspace then list[#list + 1] = { id = m.active_workspace.id, monitor = m } end
        end
        return list
    end,
    get_windows = function() return WINDOWS end,
    get_window = function(sel)
        for _, w in ipairs(WINDOWS) do if sel == "address:" .. w.address then return w end end
    end,
    get_devices = function() return { { type = "keyboard", main = true, name = "kb", caps_lock = false, num_lock = true } } end,
    get_cursor_pos = function() return { x = 100, y = 100 } end,
    get_monitor_at_cursor = function() return SCREENS[FOCUS] or SCREENS[1] end,
    animation = function() end,
    env = function(k, v) check(type(k) == "string" and type(v) == "string", "hl.env: not strings"); ENV[k] = v end,
    dsp = dsp,
    plugin = plugin and { hyprbars = { add_button = function(b) check(b.icon and b.action, "add_button") end } } or {},
}
L

cat >"$t/run.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
-- As Caelestia's hyprland.lua: hypr-vars.lua's values over its variables, then hypr-user.lua (Hyprland's require
-- turns a module's error into a config error; here it's a failure of the test)
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
fire("hyprland.start")
for _, w in ipairs(WINDOWS) do
    fire("window.open", w); fire("window.fullscreen", w); fire("window.active", w); fire("window.minimize", w, true)
end
for _, k in ipairs({ 133, 64, 78, 30 }) do fire("input.keyboard.key", k, 0, 1); fire("input.keyboard.key", k, 0, 0) end
fire("monitor.added", SCREENS[2]); fire("monitor.layout_changed")
-- What scripts call through hyprctl eval (how-it-works' Lua API), with the arguments they pass
dots.focus_window("0x3", true); dots.focus_window("0xdead")
dots.focus_app("org.gnome.Nautilus", "Files", true); dots.focus_app(nil, nil, false)
dots.maximise_window(); dots.minimise_window(); dots.refit_maximised(); dots.toggle_window_mode(); dots.toggle_window_mode()
dots.titlebar_drag_start("0x3", "before"); dots.goto_workspace(13); dots.goto_workspace(1); dots.clean_workspace(2)
dots.spotify_silent_set(true); dots.spotify_silent_set(false); dots.spotify_hide("dead"); dots.spotify_show()
dots.minimise_launcher("0xdead"); dots.open_retry("0x4"); dots.task_manager()
-- Window peek (the shell's WindowPeek.qml): the other windows on that window's screen tagged see-through, then none
local function peeked()
    local t = {}
    for _, w in ipairs(WINDOWS) do
        for _, g in ipairs(w.tags) do if g:match("^dots%-peek") then t[#t + 1] = w.address .. "=" .. g end end
    end
    table.sort(t)
    return table.concat(t, ",")
end
-- (its tags' rules made at the first peek, after every rule of the config: their opaque = false beats LibreWolf's opaque)
local rules_before = #WINDOW_RULES
for i = 1, rules_before do
    if tostring(WINDOW_RULES[i].match.tag):match("^dots%-peek") then io.write("peek rule made as the config loads\n") end
end
local function blur() return tostring(CONFIG["decoration.blur.ignore_opacity"]) end
local function run_timers() local q = HELD_TIMERS; HELD_TIMERS = {}; for _, fn in ipairs(q) do fn() end end
dots.peek_screen("DP-1", "0x1"); io.write("peeked ", peeked(), " blur over opacity ", blur(), "\n")
local made = {}
for i = rules_before + 1, #WINDOW_RULES do
    local r = WINDOW_RULES[i]
    made[#made + 1] = tostring(r.name) .. ":" .. tostring(r.match.tag) .. ":" .. tostring(r.opacity) .. ":" .. tostring(r.opaque)
end
io.write("peek rules ", table.concat(made, ","), "\n")
PEEK_TAGS = {}
dots.peek_screen("DP-1", "0x2"); io.write("peeked then ", peeked(), "\n")
io.write("peek tags then ", table.concat(PEEK_TAGS, ","), "\n")
io.write("peek rules after another peek ", #WINDOW_RULES - rules_before, "\n")
HOLD_TIMERS = true
dots.peek_end(); io.write("peek ending ", peeked(), " blur over opacity ", blur(), "\n")
run_timers(); io.write("peek ended ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek_screen("DP-1", "0x1", "0x5"); io.write("peek screen ", peeked(), "\n")
dots.peek_screen("DP-1"); io.write("peek screen bare ", peeked(), "\n")
-- (an end's clean-up, due after its fade back, left alone by a peek meanwhile)
dots.peek_end(); dots.peek_screen("DP-1", "0x1"); run_timers(); io.write("peek again meanwhile ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek_screen("NOPE-1", "0x1"); run_timers(); io.write("peek of no screen ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek_screen("NO-SCREEN", "0xdead"); run_timers(); io.write("peek on no screen ", peeked(), "\n")
-- (the blur setting already off in the config: left off)
CONFIG["decoration.blur.ignore_opacity"] = false
dots.peek_screen("DP-1", "0x1"); dots.peek_end(); run_timers(); io.write("peek with the blur setting off ", blur(), "\n")
-- (each tag that makes a window opaque, as Hyprland reports a rule's tag live (with its star): faded back whole)
local spot
for _, w in ipairs(WINDOWS) do if w.address == "0x5" then spot = w end end
for _, tag in ipairs({ "none", "opaque", "dots_opaque*", "xwl_popup*", "game*" }) do
    spot.tags = tag == "none" and {} or { tag }
    dots.peek_screen("DP-1", "0x1"); dots.peek_end(); io.write("peek ending with ", tag, " ", peeked(), "\n"); run_timers()
end
spot.tags = {}
-- (an end with nothing peeked, as the shell's start sends: the blur setting not touched, nothing queued)
CONFIG["decoration.blur.ignore_opacity"] = true
dots.peek_end(); io.write("peek end of nothing ", blur(), " ", #HELD_TIMERS, "\n")
-- (a peek that faded nothing, each window on that screen kept: its end still sets the blur back)
dots.peek_screen("HDMI-A-1", "0x3", "0x4"); io.write("peek of none faded ", peeked(), " ", blur(), "\n")
dots.peek_end(); run_timers(); io.write("peek of none ended ", blur(), "\n")
HOLD_TIMERS = false
-- The second screen unplugged: its windows come back to 1-10, maximised ones refit, Super+N on one screen
SCREENS = { SCREENS[1] }
fire("monitor.removed"); dots.refit_maximised(); dots.goto_workspace(13)
for _, b in ipairs(binds) do io.write("bind ", b, "\n") end
for keys, actions in pairs(BIND_ACTIONS) do
    for _, a in ipairs(actions) do
        if type(a) == "table" and a[1] == "global" and a[2] == "caelestia:launcherInterrupt" then io.write("interrupt ", keys, "\n") end
    end
end
for _, e in ipairs(config_errors) do io.write("config error ", e, "\n") end
for _, tag in ipairs(hidden_rules) do io.write("hidden rule tag ", tag, "\n") end
for _, g in ipairs(unset_gestures) do io.write("gesture unset ", g, "\n") end
for name, f in pairs(dots) do if type(f) == "function" then io.write("function ", name, "\n") end end
if HW_CURSORS ~= nil then io.write("no_hardware_cursors ", tostring(HW_CURSORS), "\n") end
if BAR_COLOR then io.write("bar_color ", BAR_COLOR, "\n") end
L

# One load: HOME with the given settings.lua (none if empty), the title bar plugin on or off, [one screen]
run_config() {
    rm -f "$t/home/.config/dots/settings.lua"
    [[ -z $1 ]] || printf '%s\n' "$1" >"$t/home/.config/dots/settings.lua"
    (cd "$t" && HOME=$t/home PLUGIN=$2 ONE_SCREEN=${3:-0} DOTS_VERIFY_CONFIG=${VERIFY:-} XDG_CONFIG_HOME=${XCH:-} XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test \
        SYSFS=${SYSFS:-$t/sys-none} lua run.lua stub.lua 2>&1)
}
# A game focused at the load (the stand-in's): the pointer drawn into the picture with lower input lag on (tearing
# allowed), the cursor layer kept with it off (no tearing to keep from it), and with the game open but another window
# focused (the pointer on another screen ghosted at that one's refresh rate)
grep -qx 'no_hardware_cursors 1' <<<"$(GAME_FOCUSED=1 run_config '' 0)" || fail "the pointer not drawn into the picture in a game"
grep -qx 'no_hardware_cursors 2' <<<"$(GAME_FOCUSED=1 run_config 'return { ["games.low_latency"] = false }' 0)" ||
    fail "the cursor layer taken away with lower input lag off"
grep -qx 'no_hardware_cursors 2' <<<"$(run_config '' 0)" || fail "the pointer drawn into the picture with another window focused"
# ...and on NVIDIA (its nvidia_drm module loaded) no tearing at all (its driver froze games that tear): the cursor
# layer kept, tearing not allowed
mkdir -p "$t/sys-nvidia/module/nvidia_drm" "$t/sys-none"; echo live >"$t/sys-nvidia/module/nvidia_drm/initstate"
rm -f "$t/config-keys"
grep -qx 'no_hardware_cursors 2' <<<"$(SYSFS=$t/sys-nvidia GAME_FOCUSED=1 run_config '' 0)" && ! grep -qx 'general.allow_tearing' "$t/config-keys" ||
    fail "tearing allowed on NVIDIA"
rm -f "$t/config-keys"
GAME_FOCUSED=1 run_config '' 0 >/dev/null; grep -qx 'general.allow_tearing' "$t/config-keys" || fail "tearing not allowed elsewhere"
good='return { ["keys.windows_next"] = { "ALT + TAB" }, ["keys.minimise"] = { "SUPER + M", "SUPER + DOWN" },
  ["keys.screenshot"] = {}, ["windows.cascade"] = true, ["windows.titlebars"] = true, ["windows.focus"] = "hover",
  ["nightlight"] = true, ["caelestia-keys.kbTerminal"] = { "SUPER + RETURN" }, ["caelestia-keys.kbGoToWs"] = { "ALT" } }'
for plugin in 0 1; do
    out=$(run_config "$good" $plugin) || fail "the config failed to load (plugin $plugin): $out"
    grep -q '^config error' <<<"$out" && fail "config errors (plugin $plugin): $(grep '^config error' <<<"$out")"
    grep -qx "bind ALT + TAB" <<<"$out" || fail "a bind from the settings is missing: $out"
    grep -qx "bind SUPER + DOWN" <<<"$out" || fail "the second key of a bind is missing"
    grep -qx "bind ALT + 3" <<<"$out" || fail "Super+N didn't follow the kbGoToWs setting"
    # A rule matching a tag beats one that doesn't, whatever the order: Spotify's hidden workspace needs a rule matching
    # Caelestia's music_player tag (Spotify has it), or that tag's workspace "unset" (user/apps.lua) wins
    grep -qx "hidden rule tag music_player" <<<"$out" || fail "Spotify's hidden start loses to the music_player tag's rule"
    # No special workspaces: Caelestia's 3-finger swipes up and down opened its general one
    grep -qx "gesture unset 3 up" <<<"$out" && grep -qx "gesture unset 3 down" <<<"$out" \
        || fail "Caelestia's special workspace swipes are still on"
    # Window peek: the other windows on that window's screen faded out (the second screen's left alone), with their
    # blur (Hyprland's setting for it off meanwhile); moving to another window straight to it (the one shown before
    # faded out, the new one back: the tag of no effect put on before the other's taken off, so Hyprland fades it); the
    # end: every window back by that tag, which is taken off with the blur setting put back once they're there (not by
    # an end a newer peek came after); only the windows named on a screen, or none; no window or screen, nothing
    p() { grep -qxF "$1" <<<"$out" || fail "window peek: want \"$1\", got: $(grep '^peek' <<<"$out")"; }
    p "peeked 0x2=dots-peek,0x5=dots-peek blur over opacity false"
    p "peeked then 0x1=dots-peek,0x2=dots-peek-back,0x5=dots-peek"
    p "peek tags then 0x1+dots-peek,0x2+dots-peek-back,0x2-dots-peek"
    p "peek ending 0x1=dots-peek-back-see,0x2=dots-peek-back,0x5=dots-peek-back-see blur over opacity false"
    p "peek ended  blur over opacity true"
    p "peek screen 0x2=dots-peek"
    p "peek screen bare 0x1=dots-peek,0x2=dots-peek,0x5=dots-peek"
    p "peek again meanwhile 0x1=dots-peek-back-see,0x2=dots-peek,0x5=dots-peek blur over opacity false"
    p "peek of no screen  blur over opacity true"
    p "peek on no screen "
    p "peek with the blur setting off false"
    p "peek ending with none 0x2=dots-peek-back,0x5=dots-peek-back-see"
    p "peek end of nothing true 0"
    p "peek of none faded  false"
    p "peek of none ended true"
    for tag in 'opaque' 'dots_opaque*' 'xwl_popup*' 'game*'; do
        p "peek ending with $tag 0x2=dots-peek-back,0x5=dots-peek-back"
    done
    # ...by rules made once, at the first peek (after the config's, LibreWolf's opaque one too), that win over opaque ones
    ! grep -q "^peek rule made as the config loads" <<<"$out" || fail "window peek's rules made as the config loads"
    p "peek rules dots-peek:dots-peek:0 override:false,dots-peek-back:dots-peek-back:1 override:false,dots-peek-back-see:dots-peek-back-see:0.95 override:false,dots-peek-back-see-full:dots-peek-back-see:1 override:false"
    p "peek rules after another peek 4"
done
# The title bars' colour from Caelestia's window opacity, kept from 0 to 1: a hand edit's 1.5 or text gave a colour
# Hyprland can't read, or an error that stopped titlebars.lua
grep -qx 'bar_color rgba(1f1f25f2)' <<<"$out" || fail "the title bars' colour not from the window opacity: $(grep bar_color <<<"$out")"
vars=$t/home/.config/hypr/variables.lua
cp "$vars" "$t/variables.orig"
for o in '1.5:ff' '-0.5:00' '"a lot":ff'; do
    sed -i "s/windowOpacity = [^,]*,/windowOpacity = ${o%:*},/" "$vars"
    out=$(run_config "$good" 1) || fail "the config failed to load with a window opacity of ${o%:*}: $(tail -4 <<<"$out")"
    grep -qx "bar_color rgba(1f1f25${o##*:})" <<<"$out" ||
        fail "the title bars' colour with a window opacity of ${o%:*}: $(grep bar_color <<<"$out")"
done
cp "$t/variables.orig" "$vars"
# Every window this config makes opaque tagged dots_opaque too: window peek fades it back to whole, not see-through
# (then a jump to whole once its tag is off)
bad=$(grep -h "opaque = true" "$here"/.config/caelestia/user/*.lua | grep -v "dots_opaque" | grep "window_rule" || true)
[[ -z $bad ]] || fail "opaque without the dots_opaque tag (window peek fades it back see-through): $bad"
# One screen (a HiDPI laptop panel alone): the same config loads with no errors
out=$(run_config "$good" 1 1) || fail "the config failed to load on one screen: $(tail -4 <<<"$out")"
grep -q '^config error' <<<"$out" && fail "config errors on one screen: $(grep '^config error' <<<"$out")"
# Every function of the Lua API table (docs/how-it-works.md) is there once the config has loaded
for f in $(grep -E '^\| `[a-z_]+\(' "$here/docs/how-it-works.md" | cut -d'|' -f2 | grep -oE '`[a-z_]+\(' | tr -d '`('); do
    grep -qx "function $f" <<<"$out" || fail "dots.$f (how-it-works' Lua API) isn't defined"
done
# The installer's rule (apps.lua) matches its main window's whole title, as Hyprland matches (RE2 FullMatch), in the
# languages it starts in; not its dialogs
python3 -I - "$here/.config/caelestia/user/apps.lua" <<'PY' || fail "the installer's window rule doesn't match its titles (whole-title match)"
import re, sys
line = next(l for l in open(sys.argv[1]) if "calamares" in l and "initial_title" in l)
pat = re.search(r'initial_title = "([^"]*)"', line).group(1).replace("\\\\", "\\")
ok = all(re.fullmatch(pat, t) for t in ("AgrOS Installer", "Instalador AgrOS", "Instalador de AgrOS", "Программа установки AgrOS", "AgrOS"))
sys.exit(0 if ok and not re.fullmatch(pat, "Error") else 1)
PY
# The apps your files open in drawn opaque (apps.lua: Caelestia's opacity left text and pictures see-through), by their
# classes as Hyprland matches them (RE2 FullMatch); not the terminal or Thunar
python3 -I - "$here/.config/caelestia/user/apps.lua" <<'PY' || fail "the apps your files open in aren't all opaque (apps.lua)"
import re, sys
text = re.sub(r'"\s*\.\.\s*"', '', open(sys.argv[1]).read())  # (a string split over lines: one)
pats = [p.replace("\\\\", "\\") for p in re.findall(r'match = \{ class = "([^"]*)" \}, opaque = true', text)]
opaque = lambda c: any(re.fullmatch(p, c) for p in pats)
want = ("org.gnome.TextEditor", "org.gnome.gthumb", "mpv", "org.gnome.FileRoller", "libreoffice-writer",
        "libreoffice-calc", "codium", "librewolf")
sys.exit(0 if all(map(opaque, want)) and not any(map(opaque, ("foot", "thunar", "orgxgnomexTextEditor"))) else 1)
PY
# ...and every one called from outside the config (scripts, the shell's overlay, the hyprbars patch) is in that table
table=$(grep -E '^\| `[a-z_]+\(' "$here/docs/how-it-works.md" | cut -d'|' -f2 | grep -oE '`[a-z_]+\(' | tr -d '`(')
for f in $(grep -rhoE 'dots\.[a-z_]+\(' "$here/.local" "$here/packages" "$here/system" 2>/dev/null | sort -u | sed 's/^dots\.//; s/($//'); do
    grep -qx "$f" <<<"$table" || fail "dots.$f is called from outside the config but isn't in the Lua API table (docs/how-it-works.md)"
done
# Caelestia's launcher interrupt on Super+scroll: the workspace keys take Super+scroll with two screens, and give the
# interrupt back only where Caelestia's own keybinds.lua binds it (its newer releases don't)
out=$(run_config "$good" 0)
grep -q '^interrupt ' <<<"$out" && fail "the launcher interrupt bound with Caelestia's keybinds.lua not binding it: $(grep '^interrupt' <<<"$out")"
mkdir -p "$t/home/.config/hypr/hyprland"
printf 'create_bind("SUPER + mouse_up", hl.dsp.global("caelestia:launcherInterrupt"))\ncreate_bind("SUPER + mouse_down", hl.dsp.global("caelestia:launcherInterrupt"))\n' \
    >"$t/home/.config/hypr/hyprland/keybinds.lua"
out=$(run_config "$good" 0)
{ grep -qx "interrupt SUPER + mouse_up" <<<"$out" && grep -qx "interrupt SUPER + mouse_down" <<<"$out"; } ||
    fail "Caelestia's launcher interrupt not given back after the workspace keys took Super+scroll"
rm "$t/home/.config/hypr/hyprland/keybinds.lua"
# ...read where Hyprland reads it ($XDG_CONFIG_HOME when set), and a bind commented out there not taken
mkdir -p "$t/xdg/hypr/hyprland"
printf 'create_bind("SUPER + mouse_up", hl.dsp.global("caelestia:launcherInterrupt"))\n-- create_bind("SUPER + mouse_down", hl.dsp.global("caelestia:launcherInterrupt"))\n' \
    >"$t/xdg/hypr/hyprland/keybinds.lua"
out=$(XCH=$t/xdg run_config "$good" 0)
grep -qx "interrupt SUPER + mouse_up" <<<"$out" || fail "Caelestia's keybinds.lua not read from \$XDG_CONFIG_HOME"
grep -qx "interrupt SUPER + mouse_down" <<<"$out" && fail "a launcher interrupt bind commented out taken"
# Settings missing, unreadable, not a table, or with odd values (a hand edit): the config still loads
for bad in '' 'return {' 'error("boom")' 'return 42' 'return { ["windows.cascade"] = "yes", ["keys.minimise"] = "SUPER + M" }' \
           'return { ["caelestia-keys.kbGoToWs"] = { "ALT", "CTRL" }, ["caelestia-keys.kbTerminal"] = 3 }' \
           'return { ["caelestia-keys.kbGoToWs"] = {} }' 'return { [1] = { "SUPER + T" }, [true] = false }'; do
    out=$(run_config "$bad" 1) || fail "settings.lua '$bad' took the config down: $(tail -4 <<<"$out")"
done
# Its notification that the settings failed to load: not when it's only a check (hypr-config-check: agros-check says it)
out=$(run_config 'return 42' 0)
grep -q "^exec dots-warn" <<<"$out" || fail "settings that failed to load not said"
# ...nor the Scroll Lock keymap made (scroll-lock keymap: files written, xkbcli run) for a check, which only loads it
mkdir -p "$t/home/.local/bin"
printf '#!/bin/sh\necho "$*" >>"%s/scroll-lock-calls"\n' "$t" >"$t/home/.local/bin/scroll-lock"
chmod +x "$t/home/.local/bin/scroll-lock"
out=$(VERIFY=1 run_config 'return 42' 0)
grep -q "^exec dots-warn" <<<"$out" && fail "a notification sent by the config check (DOTS_VERIFY_CONFIG)"
[[ ! -e $t/scroll-lock-calls ]] || fail "the Scroll Lock keymap made by the config check: $(cat "$t/scroll-lock-calls")"
run_config 'return {}' 0 >/dev/null
grep -qx keymap "$t/scroll-lock-calls" || fail "the Scroll Lock keymap not made at a real load"
rm "$t/home/.local/bin/scroll-lock" "$t/scroll-lock-calls"
# Synced screens: what the keys, the workspace event, a screen unplugged and plugged back and the laptop lid do, played
# on the stand-in (a reload: the config loaded again in the same Lua, its handlers and binds from scratch, as Hyprland
# drops them; what's kept for a screen survives it in XDG_RUNTIME_DIR)
mkdir -p "$t/run/hypr/test"
cat >"$t/sync.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local function load()
    for name in pairs(package.loaded) do
        if name == "hypr-user" or name:match("^user%.") then package.loaded[name] = nil end
    end
    handlers, binds, BIND_ACTIONS, MONITOR_RULES = {}, {}, {}, {}
    require("hypr-user")
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
load()
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
local function press(key)
    for _, a in ipairs(BIND_ACTIONS[key] or {}) do if type(a) == "function" then a() else hl.dispatch(a) end end
end
local function shown() return SCREENS[1].active_workspace.id .. "," .. SCREENS[2].active_workspace.id end
local function check(what, got, want)
    if got ~= want then error(what .. ": " .. tostring(got) .. ", not " .. tostring(want), 0) end
end
local function win(address, workspace)
    return { address = address, class = "foot", title = address, floating = true, fullscreen = 0, pid = 1, tags = {},
             workspace = type(workspace) == "number" and ws(workspace) or { name = workspace, special = true },
             monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 800, y = 600 }, focus_history_id = 1 }
end
local function where(address)
    for _, w in ipairs(WINDOWS) do if w.address == address then return w.workspace.name end end
end

-- Next/previous stay on the screen's own 10: from the 2nd screen's 20 back to 19 (the 1st to 9), and from there
-- forward again, stopping at 20 (not on to 21, which isn't the 2nd screen's)
FOCUS = 2; SCREENS[1].active_workspace = ws(10); SCREENS[2].active_workspace = ws(20)
press("CTRL + SUPER + Left"); check("previous workspace on the 2nd screen", shown(), "9,19")
press("SUPER + mouse_down"); press("CTRL + SUPER + Right"); check("next workspace past the 10th", shown(), "10,20")
check("focus after next/previous", FOCUS, 2)
-- Super+Alt+N on the 2nd screen: its own N (13)
WINDOWS = { win("0xa", 20) }; ACTIVE = WINDOWS[1]
press("SUPER + ALT + 3"); check("Super+Alt+3 on the 2nd screen", where("0xa"), "13")
press("SUPER + ALT + Page_Down"); check("window to the next workspace", where("0xa"), "14")
-- Any workspace change on one screen brings the other to its column (a window followed, a swipe, a script)
SCREENS[2].active_workspace = ws(14); fire("workspace.active", ws(14))
check("the other screen after a workspace change", shown(), "4,14")
-- Off the end of the 2nd screen's 10 (the swipe makes 21 there): back on its 10th, the other screen on its own
SCREENS[2].active_workspace = ws(21); fire("workspace.active", ws(21))
check("past the last workspace", shown(), "10,20")

-- The 2nd screen unplugged: its workspaces with windows (11, 13 with one minimised, 15, 17) onto the 1st screen's
-- empty ones in order (3, 4, 5, 6: 1 and 2 have windows), not onto the same numbers
local first, second = SCREENS[1], SCREENS[2]
WINDOWS = { win("0x1", 1), win("0x2", 2), win("0xb", 11), win("0xc", 13), win("0xd", "special:minimised-13"), win("0xe", 15),
            win("0xf", 17) }
WINDOWS[#WINDOWS + 1] = win("0x9", 3); WINDOWS[#WINDOWS].pinned = true  -- (a desktop widget: on every workspace)
SCREENS = { first }; fire("monitor.removed", second)
-- (its command, run below by sh with hypr-reload and hyprctl stand-ins)
local rf = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/screens-reload", "w"); rf:write(SCREENS_RELOAD or ""); rf:close()
check("unplugged 11", where("0xb"), "3"); check("unplugged 13", where("0xc"), "4")
check("unplugged minimised on 13", where("0xd"), "special:minimised-4"); check("unplugged 15", where("0xe"), "5")
check("unplugged 17", where("0xf"), "6"); check("pinned window", where("0x9"), "3")
-- A different screen plugged in (the reload, then what the config runs after it): nothing comes to it
local other = { id = 2, name = "HDMI-A-1", description = "Third Screen", x = 1920, y = 0, width = 1920, height = 1080,
                scale = 1, transform = 0, active_workspace = ws(11) }
SCREENS = { first, other }; load(); dots.screens_changed()
check("window restored onto a different screen", where("0xe"), "5")
SCREENS = { first }; load()
-- The same screen back: what's still where it was put returns to it; one moved since stays, a closed one is skipped
for i, w in ipairs(WINDOWS) do if w.address == "0xb" then table.remove(WINDOWS, i) break end end
hl.dispatch(hl.dsp.window.move({ window = "address:0xc", workspace = 7 }))
second.active_workspace = ws(11); SCREENS = { first, second }; load(); dots.screens_changed()
check("restored minimised", where("0xd"), "special:minimised-13"); check("restored 15", where("0xe"), "15")
check("restored 17", where("0xf"), "17"); check("moved since", where("0xc"), "7")
-- The 1st screen unplugged: the 2nd, left alone, shows its column on 1-10, where its windows went (not an empty 15)
second.active_workspace = ws(15); load(); SCREENS = { second }; fire("monitor.removed", first)
FOCUS = 1; load(); dots.screens_changed()
check("the screen left when the 1st is unplugged", second.active_workspace.id, 5); check("its window", where("0xe"), "5")
-- Plugged back: the screen that stayed keeps the column it showed (its 5 becoming 15, the 1st's own 5 back to it)
first.active_workspace = ws(1); SCREENS = { first, second }; fire("monitor.added", first)
FOCUS = 2; load(); dots.screens_changed()
check("the column after the 1st is plugged back", shown(), "5,15")

-- The laptop lid closed with another screen: the panel off by a rule, after any other rule for it (at load, as at
-- every reload); opened: on again. Closed with the panel alone: left on (logind suspends)
local panel = { id = 3, name = "eDP-1", description = "Some Panel", x = 0, y = 1080, width = 2560, height = 1600, scale = 1.6,
                transform = 0, enabled = true, active_workspace = ws(11) }
local function last_rule(output)
    local found
    for _, r in ipairs(MONITOR_RULES) do if r.output == output then found = r end end
    return found and found.disabled
end
SCREENS = { first, panel }; LID = "state:      closed\n"; load()
check("panel at a load with the lid closed", last_rule("eDP-1"), true)
-- From the switch: the rule at once, no reload (it takes a game out of fullscreen); opened, only the panel the close
-- turned off on again
LID = "state:      open\n"; load(); RELOADED = nil; LID = "state:      closed\n"; press("switch:on:Lid Switch")
check("the lid closing turns the panel off", last_rule("eDP-1"), true); check("the lid closing reloads", RELOADED, nil)
panel.enabled = false; LID = "state:      open\n"; press("switch:off:Lid Switch")
check("the lid opening turns the panel on", last_rule("eDP-1"), false); check("the lid opening reloads", RELOADED, nil)
local rules = #MONITOR_RULES; press("switch:off:Lid Switch")
check("opened again: no rule", #MONITOR_RULES, rules); load()
check("panel at a load with the lid open", last_rule("eDP-1"), nil)
panel.enabled = true; SCREENS = { panel }; LID = "state:      closed\n"; load()
check("panel alone with the lid closed", last_rule("eDP-1"), nil)
-- The other screen unplugged while the panel was off: no rule of its own, so the host file's (mode, scale) turns it on,
-- not one with nothing but "on" replacing it
panel.enabled = false; load()
check("panel off, alone, with the lid closed", last_rule("eDP-1"), nil)
-- A host file's rule for the panel by make and model: off with it, and on again last (Hyprland applies the latest rule
-- that matches a screen: the by-name one the close added has none of its mode or scale)
local hf = io.open("/proc/sys/kernel/hostname"); local host = hf:read("l"); hf:close()
local host_file = home .. "/.config/caelestia/user/hosts/" .. host .. ".lua"
local saved = io.open(host_file); local kept = saved and saved:read("a"); if saved then saved:close() end
local function rule_of(output)
    local found
    for _, r in ipairs(MONITOR_RULES) do if r.output == output then found = r end end
    return found or {}
end
-- (no rule by its name before: the one closing it made from the one that applied, else opened it got Hyprland's
-- defaults, placed and sized anew; with none for it in the host file, any screen's)
local w = io.open(host_file, "w"); w:write(""); w:close()
panel.enabled = true; SCREENS = { first, panel }; LID = "state:      closed\n"; load()
check("the panel's rule from any screen's", rule_of("eDP-1").position, "auto")
w = io.open(host_file, "w"); w:write('dots.monitor({ output = "desc:Some Panel", mode = "2560x1600@240", scale = 1.6 })\n'); w:close()
panel.enabled = true; SCREENS = { first, panel }; LID = "state:      open\n"; load()
LID = "state:      closed\n"; press("switch:on:Lid Switch")
check("the lid closing turns the panel's desc: rule off", last_rule("desc:Some Panel"), true)
check("the panel's rule from its desc: one", rule_of("eDP-1").mode .. " " .. rule_of("eDP-1").scale, "2560x1600@240 1.6")
panel.enabled = false; LID = "state:      open\n"; press("switch:off:Lid Switch")
local last = MONITOR_RULES[#MONITOR_RULES]
check("the lid opening: the panel's desc: rule on, last", last.output .. " " .. tostring(last.disabled), "desc:Some Panel false")
if kept then w = io.open(host_file, "w"); w:write(kept); w:close() else os.remove(host_file) end
for _, e in ipairs(config_errors) do error("config error " .. e, 0) end
L
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua sync.lua stub.lua 2>&1) \
    || fail "synced screens: $out"
# The screen change's command: screens_changed run once the config reloaded, not when hypr-reload failed (screens_changed
# found the config not reloaded and asked again: each second, through a game); left to a reload waiting for a game (3),
# once that one is done
[[ -s $t/run/screens-reload ]] || fail "a screen unplugged ran no reload"
mkdir -p "$t/sr/home/.local/bin" "$t/sr/bin"
printf '#!/bin/sh\necho "hyprctl $*" >>"%s/sr/ran"\n' "$t" >"$t/sr/bin/hyprctl"
printf '#!/bin/sh\necho reload >>"%s/sr/ran"\nexit "$RC"\n' "$t" >"$t/sr/home/.local/bin/hypr-reload"
chmod +x "$t/sr/bin/hyprctl" "$t/sr/home/.local/bin/hypr-reload"
screens_reload() { HOME=$t/sr/home XDG_RUNTIME_DIR=$t/sr PATH=$t/sr/bin:$PATH RC=$1 sh -c "$(cat "$t/run/screens-reload")"; }
for rc in 0 1; do
    : >"$t/sr/ran"; screens_reload $rc || true
    want=reload; [[ $rc == 0 ]] && want=$'reload\nhyprctl eval dots.screens_changed()'
    [[ $(cat "$t/sr/ran") == "$want" ]] || fail "hypr-reload exiting $rc: $(cat "$t/sr/ran")"
done
: >"$t/sr/ran"; : >"$t/sr/hypr-reload-pending"
flock "$t/sr/hypr-reload-pending" sh -c "until [ -e '$t/sr/game-closed' ]; do sleep 0.1; done" &
for _ in {1..50}; do flock -n "$t/sr/hypr-reload-pending" true || break; sleep 0.1; done
screens_reload 3 &
sleep 1
[[ $(cat "$t/sr/ran") == reload ]] || fail "screens_changed run while another reload waited for the game: $(cat "$t/sr/ran")"
touch "$t/sr/game-closed"; wait
[[ $(cat "$t/sr/ran") == $'reload\nhyprctl eval dots.screens_changed()' ]] ||
    fail "screens_changed not run once the reload waiting for the game was done: $(cat "$t/sr/ran")"
# Window drags: edges resize (Hyprland's resize_on_border on, off while a game is open), and a maximised window dragged stops being maximised:
# moved (any title bar, the plugin's hook), shrunk to the standard size round the pointer; resized, only untagged
cat >"$t/drag.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local general, cursor, config = {}, {}, hl.config
hl.config = function(c)
    config(c)
    for k, v in pairs(c.general or {}) do general[k] = v end
    for k, v in pairs(c.cursor or {}) do cursor[k] = v end
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
local function check(what, got, want)
    if got ~= want then error(what .. ": " .. tostring(got) .. ", not " .. tostring(want), 0) end
end
-- Edges off while a game is open (its 16 px grab band took clicks on the next screen and in the screen's corners):
-- the stand-in's game 0x2 at the load, closing (still listed then), another opening, a non-game, a window tagged later
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
check("edges with a game open at load", general.resize_on_border, false)
-- (and the pointer drawn into the picture while the game has the focus: no tearing, the lower input lag, with the
-- cursor layer showing one; the cursor layer with anything else focused, as at the load: another screen's pointer, out
-- of the game, ghosted at that screen's refresh rate)
local game = WINDOWS[2]
check("the cursor layer with the game open, not focused", cursor.no_hardware_cursors, 2)
ACTIVE = game; fire("window.active", game)
check("software pointer with the game focused", cursor.no_hardware_cursors, 1)
ACTIVE = WINDOWS[1]; fire("window.active", WINDOWS[1])
check("the cursor layer back once something else is focused", cursor.no_hardware_cursors, 2)
ACTIVE = game; fire("window.active", game)
ACTIVE = nil; fire("window.close", game); WINDOWS = { WINDOWS[1] }
check("edges once the game closed", general.resize_on_border, true)
check("the cursor layer back once the game closed", cursor.no_hardware_cursors, 2)
local other = { address = "0x7", class = "org.gnome.Calculator", title = "c", floating = true, fullscreen = 0, pid = 1,
                tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 400, y = 300 },
                focus_history_id = 1 }
WINDOWS[#WINDOWS + 1] = other; fire("window.open", other)
check("edges with a non-game opened", general.resize_on_border, true)
WINDOWS[#WINDOWS + 1] = game; fire("window.open", game)
check("edges with a game opened", general.resize_on_border, false)
fire("window.close", game); table.remove(WINDOWS)
check("edges after the last game", general.resize_on_border, true)
other.tags = { "game" }; fire("window.update_rules", other)
check("edges with a window tagged a game later", general.resize_on_border, false)
-- What a drag start sends: the tag change, the size and the place
local sent, dispatch = {}, hl.dispatch
hl.dispatch = function(d) sent[#sent + 1] = d; dispatch(d) end
local function result()
    local r = {}
    for _, d in ipairs(sent) do
        if d[1] == "window.tag" then r.tag = d[2].tag
        elseif d[1] == "window.resize" then r.w, r.h = d[2].x, d[2].y
        elseif d[1] == "window.move" then r.x, r.y = d[2].x, d[2].y end
    end
    sent = {}
    return r
end
-- The settings (Nexus) open at the standard size, 60% of the screen's height, not the near full screen Nexus asks for;
-- another Quickshell window (a pop-up) keeps its own size
local nexus = { address = "0xn1", class = "org.quickshell", title = "Nexus — Home", floating = true, fullscreen = 0, pid = 1,
                tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 60, y = 30 }, size = { x = 1800, y = 1004 } }
WINDOWS = { nexus }
sent = {}; fire("window.open", nexus)
local r0 = result()
check("settings open at the standard height", r0.h, math.floor(SCREENS[1].height * 0.6 + 0.5))
local qpop = { address = "0xn2", class = "org.quickshell", title = "Updates", floating = true, fullscreen = 0, pid = 1,
               tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 600, y = 300 }, size = { x = 700, y = 500 } }
WINDOWS = { qpop }
sent = {}; fire("window.open", qpop)
check("another Quickshell window keeps its size", result().h, nil)
WINDOWS = {}
-- A maximised window filling the first screen inside the gaps, below its title bar
local win = { address = "0x9", class = "org.gnome.TextEditor", title = "t", floating = true, fullscreen = 0, pid = 1,
              tags = { "maximised" }, workspace = ws(1), monitor = SCREENS[1], at = { x = 11, y = 83 },
              size = { x = 1898, y = 986 }, focus_history_id = 0 }
WINDOWS = { win }
local r = (dots.window_drag_start("0x9", "resize") or true) and result()
check("resized: tag", r.tag, "-maximised"); check("resized: new size", r.w, nil)
-- Moved by the app's header 3/4 across, 20 px down: smaller, the pointer still 3/4 across and 20 px down
hl.get_cursor_pos = function() return { x = 11 + 1898 * 0.75, y = 83 + 20 } end
r = (dots.window_drag_start("0x9", "move") or true) and result()
check("moved: tag", r.tag, "-maximised")
check("moved: smaller", r.w and r.w < 1898 and r.h < 986, true)
check("moved: pointer across", math.abs((11 + 1898 * 0.75 - r.x) / r.w - 0.75) < 0.01, true)
check("moved: pointer down", math.abs(83 + 20 - r.y - 20) <= 1, true)
-- Not maximised: left be; the plugin's own bar's call does the same as a move
win.tags = {}
r = (dots.window_drag_start("0x9", "move") or true) and result()
check("not maximised: tag", r.tag, nil); check("not maximised: size", r.w, nil)
win.tags = { "maximised" }
r = (dots.titlebar_drag_start("0x9", "before") or true) and result()
check("title bar drag: tag", r.tag, "-maximised")
-- The floating/tiling switch, both ways, leaves a pinned window be (picture-in-picture): tiled, it lost its pin
local pip = { address = "0xd", class = "librewolf", title = "Picture-in-Picture", floating = true, pinned = true, fullscreen = 0,
              pid = 1, tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 1500, y = 800 },
              size = { x = 400, y = 225 }, focus_history_id = 1 }
WINDOWS = { pip }; sent = {}
dots.toggle_window_mode(); dots.toggle_window_mode()
for _, d in ipairs(sent) do
    local w = (d[2] or {}).window
    if w == pip or w == "address:0xd" then error("the floating/tiling switch on a pinned window: " .. d[1], 0) end
end
-- Minimised, it's unpinned first (Hyprland keeps a pinned window out of special workspaces: it stayed put), and pinned
-- again as it comes back (the dock's focus)
local function steps()
    local s = {}
    for _, d in ipairs(sent) do
        local a = d[2] or {}
        if d[1]:match("^window%.") then s[#s + 1] = d[1] .. ":" .. tostring(a.action or a.tag or a.workspace) end
    end
    sent = {}
    return table.concat(s, " ")
end
dots.minimise_window(pip)
check("pinned minimised", steps(), "window.pin:off window.tag:+minimised_pinned window.move:special:minimised-1")
pip.pinned, pip.tags = false, { "minimised_pinned" }
fire("window.active", pip)
check("pinned restored", steps(), "window.move:1 window.tag:-minimised_pinned window.pin:on window.alter_zorder:nil")
-- Maximised, minimised, the screen shrunk while it was away: it comes back filling the screen as it is now
local mx = { address = "0xm", class = "thunar", title = "m", floating = true, fullscreen = 0, pid = 1, tags = { "maximised" },
             workspace = ws(1), monitor = SCREENS[1], at = { x = 11, y = 83 }, size = { x = 1898, y = 986 }, focus_history_id = 5 }
WINDOWS[#WINDOWS + 1] = mx
dots.minimise_window(mx); sent = {}
local was_w = SCREENS[1].width
SCREENS[1].width = 1600
fire("window.active", mx)
local back_w
for _, d in ipairs(sent) do if d[1] == "window.resize" then back_w = d[2].x end end
sent, SCREENS[1].width = {}, was_w
table.remove(WINDOWS)
check("maximised, minimised, back after the screen shrank: fits it", back_w, 1600 - 22)
-- ...a snapped one (left half, the free part it was placed for noted) the same: back as the left half of the screen
-- as it is now, scaled from that note
local sn = { address = "0xn", class = "thunar", title = "n", floating = true, fullscreen = 0, pid = 1,
             tags = { "snapped", "snap_left", "snaparea_DP-1_11_51_1898_1018_12_32" }, workspace = ws(1), monitor = SCREENS[1],
             at = { x = 11, y = 83 }, size = { x = 943, y = 986 }, focus_history_id = 6 }
WINDOWS[#WINDOWS + 1] = sn
dots.minimise_window(sn); sent = {}
SCREENS[1].width = 1600
fire("window.active", sn)
back_w = nil
for _, d in ipairs(sent) do if d[1] == "window.resize" then back_w = d[2].x end end
sent, SCREENS[1].width = {}, was_w
table.remove(WINDOWS)
check("snapped, minimised, back after the screen shrank: the left half of it", back_w and math.abs(back_w - (1578 - 12) / 2) <= 1, true)
-- An app's minimise request with no window to it (gone by then): nothing, not the focused window minimised instead
fire("window.minimize", nil, true)
check("minimise request with no window", steps(), "")
-- An app opened over a game covering its screen (Overwatch borderless, Hyprland's fullscreen taken off it for the app,
-- the app behind it): the game minimised, as Alt+Tab does; not for a menu (xwl_popup), a window of the game's own (a
-- game too), nor over a game in a window; a fullscreen one in a window's size still covers it
local game = { address = "0xg", class = "steam_app_2357570", title = "Overwatch", floating = true, fullscreen = 0, pid = -1,
               tags = { "game*" }, workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 },
               size = { x = 1920, y = 1080 }, focus_history_id = 1 }
local function over_game(tags, size, fullscreen, event)
    game.size, game.fullscreen, game.workspace = size or { x = 1920, y = 1080 }, fullscreen or 0, ws(1)
    local app = { address = "0xa", class = "thunar", title = "a", floating = false, fullscreen = 0, pid = -1, tags = tags or {},
                  workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 800, y = 600 }, focus_history_id = 0 }
    WINDOWS, sent = { game, app }, {}
    fire(event or "window.open", app)
    local minimised = false
    for _, d in ipairs(sent) do
        local a = d[2] or {}
        if d[1] == "window.move" and (a.window == game or a.window == "address:0xg")
            and tostring(a.workspace):find("^special:minimised") then minimised = true end
    end
    sent, WINDOWS = {}, {}
    return minimised
end
check("an app opened over a game covering the screen: the game minimised", over_game(), true)
check("a menu over a game: the game stays", over_game({ "xwl_popup*" }), false)
check("the game's own window: the game stays", over_game({ "game*" }), false)
check("over a game in a window: it stays", over_game(nil, { x = 1280, y = 720 }), false)
check("over a fullscreen game: minimised", over_game(nil, { x = 1280, y = 720 }, 2), true)
check("an app already open focused over a fullscreen game: the game minimised", over_game(nil, nil, 2, "window.active"), true)
check("the game's own window focused: the game stays", over_game({ "game*" }, nil, 2, "window.active"), false)
-- A minimised game brought back (the dock focuses it on its hidden workspace): moving it back hands the focus to the
-- app on its workspace for a moment, which isn't an app focused over it: it stays back, not minimised again
do
    local app = { address = "0xa", class = "librewolf", title = "a", floating = true, fullscreen = 0, pid = -1, tags = {},
                  workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 800, y = 600 }, focus_history_id = 0 }
    game.size, game.fullscreen, game.workspace = { x = 1920, y = 1080 }, 0, ws(nil, "special:minimised-1")
    WINDOWS = { game, app }
    local plain = hl.dispatch
    hl.dispatch = function(d)
        plain(d)
        local a = d[2] or {}
        if d[1] == "window.move" and (a.window == game or a.window == "address:0xg") and a.workspace then
            game.workspace = type(a.workspace) == "number" and ws(a.workspace) or ws(nil, a.workspace)
            if game.workspace.id then fire("window.active", app) end
        end
    end
    fire("window.active", game)
    hl.dispatch = plain
    check("a minimised game brought back: stays back", game.workspace.name, "1")
    sent, WINDOWS = {}, {}
end
-- A game Hyprland took out of fullscreen (another window focused) is fullscreen again as you go back to it, while it
-- still covers the screen; not one made smaller in its own settings, nor a game that never left fullscreen. Also one
-- found out of fullscreen at a config load (dots.games_out_of_fullscreen)
local function back_to(size, left, scan)
    game.size, game.workspace, game.address = size or { x = 1920, y = 1080 }, ws(1), "0xg" .. tostring(math.random(1e6))
    WINDOWS, sent = { game }, {}
    game.fullscreen = 0
    if left then fire("window.fullscreen", game) end
    if scan then dots.games_out_of_fullscreen() end
    sent = {}
    fire("window.active", game)
    local full = false
    for _, d in ipairs(sent) do
        local a = d[2] or {}
        if d[1] == "window.fullscreen" and a.mode == "fullscreen" and a.action == "set" then full = true end
    end
    sent, WINDOWS = {}, {}
    return full
end
check("a game out of fullscreen, gone back to: fullscreen again", back_to(nil, true), true)
check("a game made smaller: stays a window", back_to({ x = 1280, y = 720 }, true), false)
check("a game that never left fullscreen: nothing", back_to(nil, false), false)
check("found out of fullscreen at a config load: fullscreen again", back_to(nil, false, true), true)
-- ...and one that left fullscreen for maximised (inside the bar and border: it doesn't cover the screen)
game.fullscreen = 1
local function back_maximised()
    game.size, game.workspace, game.address = { x = 1890, y = 1030 }, ws(1), "0xmax"
    WINDOWS, sent = { game }, {}
    fire("window.fullscreen", game)
    sent = {}
    fire("window.active", game)
    local full = false
    for _, d in ipairs(sent) do if d[1] == "window.fullscreen" and (d[2] or {}).action == "set" then full = true end end
    sent, WINDOWS, game.fullscreen = {}, {}, 0
    return full
end
check("a game out of fullscreen to maximised, gone back to: fullscreen again", back_maximised(), true)
-- ...and put back again (a moment later, at most 3 times) when it drops it by itself right after, still focused
-- (exclusive fullscreen, not yet active to itself); not once another window has the focus
local other_win = { address = "0xow", class = "foot", workspace = ws(11), fullscreen = 0, tags = {} }
local function drops_after(focused, times)
    game.size, game.workspace, game.address, game.fullscreen = { x = 1920, y = 1080 }, ws(1), "0xdrop" .. tostring(math.random(1e6)), 0
    WINDOWS, ACTIVE, sent = { game, other_win }, game, {}
    fire("window.fullscreen", game)
    fire("window.active", game)
    ACTIVE = focused
    local n = 0
    for _ = 1, times do
        sent = {}
        fire("window.fullscreen", game)
        for _, d in ipairs(sent) do if d[1] == "window.fullscreen" and (d[2] or {}).action == "set" then n = n + 1 end end
    end
    sent, WINDOWS, ACTIVE = {}, {}, nil
    return n
end
check("a game put back, dropping it again by itself, focused: put back again", drops_after(game, 1), 1)
check("...dropping it 5 times: put back 3 times", drops_after(game, 5), 3)
check("...dropping it as another window is focused: left", drops_after(other_win, 1), 0)
-- ...but not once it closed: a new window given its address isn't made fullscreen
game.address, WINDOWS = "0xreused", { game }
game.fullscreen = 0
fire("window.fullscreen", game)
fire("window.close", game)
sent = {}
fire("window.active", game)
local refull = false
for _, d in ipairs(sent) do if d[1] == "window.fullscreen" and (d[2] or {}).action == "set" then refull = true end end
sent, WINDOWS = {}, {}
check("a closed game's address given to a new window: not made fullscreen", refull, false)
-- A game going fullscreen takes the focus the first time only: one in exclusive fullscreen leaves it and comes back each
-- time it loses focus, and focusing it again pulled the focus back from the other screen, several times a second
game.address, game.workspace, game.fullscreen, WINDOWS = "0xfirst", ws(1), 2, { game }
local function focused_on_fullscreen()
    sent = {}
    fire("window.fullscreen", game)
    local f = false
    for _, d in ipairs(sent) do if d[1] == "focus" then f = true end end
    sent = {}
    return f
end
check("a game going fullscreen: focused", focused_on_fullscreen(), true)
check("the same game fullscreen again: not focused again", focused_on_fullscreen(), false)
WINDOWS = {}
-- A game leaving fullscreen while another window has the focus: in exclusive fullscreen (crossing.lua keeps the
-- pointer in it); one leaving it while focused (its own settings), or minimised to a hidden workspace, isn't
local other = { address = "0xother", class = "foot", workspace = ws(11), fullscreen = 0, tags = {} }
local function exclusive_after(focused, workspace)
    game.address, game.workspace, game.fullscreen = "0xex" .. tostring(math.random(1e6)), workspace or ws(1), 0
    WINDOWS, ACTIVE = { game, other }, focused
    fire("window.fullscreen", game)
    local got = dots.exclusive_fullscreen[game.address] == true
    WINDOWS, ACTIVE = {}, nil
    return got
end
check("a game leaving fullscreen as another window is focused: exclusive", exclusive_after(other), true)
check("a game leaving fullscreen while focused: not exclusive", exclusive_after(game), false)
check("a game minimised to a hidden workspace: not exclusive", exclusive_after(other, { id = -98, name = "special:minimised-1" }), false)
-- A notification's click: the app's most recently used window, not one never focused (Hyprland's focus_history_id -1:
-- a launcher minimised as it opened), which came first
local function app_win(address, history)
    return { address = address, class = "eadesktop.exe", title = "EA", floating = true, fullscreen = 0, pid = 1, tags = {},
             workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 800, y = 600 },
             focus_history_id = history }
end
WINDOWS = { app_win("0xe1", -1), app_win("0xe2", 3), app_win("0xe3", 1) }
dots.focus_app("eadesktop.exe", "EA app", true)
local focused
for _, d in ipairs(sent) do
    if d[1] == "focus" then focused = d[2].window and d[2].window.address end
end
check("notification click: the most recent window", focused, "0xe3")
sent = {}
-- An app named alone (no launcher entry, launch false: a notification of a Quickshell app named by its class): the open
-- window, by its class, to the front; none open, nothing, never the app launched from here
local upd = app_win("0xe4", 2)
upd.class, upd.title = "updates", "Updates"
WINDOWS = { app_win("0xe1", 1), upd }
dots.focus_app(nil, "updates")
focused = nil
for _, d in ipairs(sent) do
    if d[1] == "focus" then focused = d[2].window and d[2].window.address end
end
check("Updates opened again: its window", focused, "0xe4")
WINDOWS, sent = { app_win("0xe1", 1) }, {}
dots.focus_app(nil, "updates")
check("Updates opened, none open yet", #sent, 0)
sent = {}
-- Snapping (floating mode, the first screen: 1920x1080, 40 px reserved at the top; gaps 10 out, 5 in, border 1 or 2):
-- let go at the left edge it takes the left half, below its title bar; dragged away, its old size back; in the top right
-- corner the top right quarter; at the top edge maximised; mid-screen nothing. Caelestia told of the drag and the zone
local events = {}
-- (the second screen away from the first while its edges are tried: a side with a screen beyond isn't a snap edge)
SCREENS[2].x = 5000
local function snap(address, x, y)
    hl.get_cursor_pos = function() return { x = x, y = y } end
    dots.window_drag_start(address, "move")
    dots.window_drag_end(address, "move")
    local r = result()
    for _, d in ipairs(sent) do if d[1] == "event" then events[#events + 1] = d[2] end end
    return r
end
local hdispatch = hl.dispatch
hl.dispatch = function(d) if d[1] == "event" then events[#events + 1] = d[2] end; hdispatch(d) end
local ed = { address = "0xa", class = "org.gnome.TextEditor", title = "t", floating = true, fullscreen = 0, pid = 1,
             tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 500, y = 400 }, size = { x = 800, y = 600 },
             focus_history_id = 0 }
WINDOWS = { ed }
local bar = dots.titlebar_height(ed)
local a = { x = 11, y = 51 }  -- (0 + 10 + 1, 40 + 10 + 1: the gaps and border inside the reserved space)
a.w, a.h = 1920 - 2 * a.x, 1080 - 40 - 2 * 11
-- (its snapping and maximised tags; the free part it was placed for, snaparea_<screen>_<x>_<y>_<w>_<h>_<seam>_<bar>, on its own)
local function tags(w) local t = {}; for _, x in ipairs(w.tags) do if not x:match("^snaparea_") then t[#t + 1] = x end end; table.sort(t); return table.concat(t, " ") end
local function areas(w) local t = {}; for _, x in ipairs(w.tags) do if x:match("^snaparea_") then t[#t + 1] = x end end; table.sort(t); return table.concat(t, " ") end
r = snap("0xa", 0, 540)
check("snapped left: tags", tags(ed), "snap_left snapped")
check("snapped left: place", r.x .. "," .. r.y, a.x .. "," .. (a.y + bar))
check("snapped left: the free part noted, once", areas(ed), "snaparea_DP-1_11_51_" .. a.w .. "_" .. a.h .. "_12_" .. bar)
check("snapped left: half, a seam between", math.abs(2 * r.w + 12 - a.w) <= 1 and r.h == a.h - bar, true)
check("drag told", table.concat(events, "|"):match("^agros_drag 1|agros_snap DP%-1 11 51 %d+ %d+|agros_drag 0|agros_snap none") ~= nil, true)
ed.at, ed.size = { x = r.x, y = r.y }, { x = r.w, y = r.h }
hl.get_cursor_pos = function() return { x = 300, y = 500 } end
dots.window_drag_start("0xa", "move")
r = result()
check("unsnapped: tags", tags(ed), ""); check("unsnapped: old size", r.w .. "x" .. r.h, "800x600")
check("unsnapped: the free part's note gone", areas(ed), "")
dots.window_drag_end("0xa", "move"); result()
ed.size, ed.tags = { x = 800, y = 600 }, {}
r = snap("0xa", 1919, 0)
check("top right quarter", r.x > 960 and r.y == a.y + bar and math.abs(2 * (r.h + bar) + 12 - a.h) <= 1, true)
dots.window_drag_start("0xa", "move"); dots.window_drag_end("0xa", "move"); result()
-- Slid along the edge mid-drag (each step: the plugin's dots.window_drag_step): from the top right corner down to the
-- right edge's middle, the preview follows (the right half told) and the window takes the right half
events = {}
hl.get_cursor_pos = function() return { x = 1919, y = 0 } end
dots.window_drag_start("0xa", "move")
hl.get_cursor_pos = function() return { x = 1919, y = 540 } end
dots.window_drag_step("0xa", "move")
dots.window_drag_end("0xa", "move")
r = result()
check("slid to the right edge: preview", table.concat(events, "|"):match("agros_snap DP%-1 %d+ 51 %d+ %d+|agros_drag 0") ~= nil, true)
check("slid to the right edge: right half", r.x > 960 and r.y == a.y + bar and r.h == a.h - bar, true)
dots.window_drag_start("0xa", "move"); dots.window_drag_end("0xa", "move"); result()
ed.size, ed.tags = { x = 800, y = 600 }, {}
r = snap("0xa", 960, 41)
check("top edge (the free part's, below the reserved 40 px) maximises", r.tag, "+maximised")
ed.tags = {}
dots.window_drag_start("0xa", "move"); dots.window_drag_end("0xa", "move"); result()
r = snap("0xa", 960, 540)
check("mid-screen: nothing", r.tag, nil)
-- The bottom edge: the bottom half, Snap Assist offering the top half (agros_assist, for the switcher); the window
-- picked there (dots.snap_to) fills it, below its title bar
events = {}
r = snap("0xa", 960, 1079)
check("bottom edge: the bottom half", tags(ed) .. " " .. tostring(r.x == a.x and r.y > 540 and math.abs(r.w - a.w) <= 1), "snap_bottom snapped true")
check("bottom half: Snap Assist offers the top half", table.concat(events, "|"):match("agros_assist DP%-1 top 0xa 11 51 %d+ %d+") ~= nil, true)
local pick = { address = "0xd", class = "thunar", title = "f", floating = true, fullscreen = 0, pid = 1, tags = {},
               workspace = ws(1), monitor = SCREENS[1], at = { x = 300, y = 300 }, size = { x = 700, y = 500 },
               focus_history_id = 1 }
WINDOWS = { ed, pick }
dots.snap_to("0xd", "top", "DP-1")
r = result()
check("Snap Assist's pick: the top half", tags(pick) .. " " .. r.x .. "," .. r.y, "snap_top snapped " .. a.x .. "," .. (a.y + bar))
check("Snap Assist's pick: half the height, a seam between", math.abs(2 * (r.h + bar) + 12 - a.h) <= 1 and math.abs(r.w - a.w) <= 1, true)
WINDOWS = { ed }
dots.window_drag_start("0xa", "move"); dots.window_drag_end("0xa", "move"); result()
ed.size, ed.tags = { x = 800, y = 600 }, {}
-- Two snapped side by side: resizing the left one moves the right one's edge with it
local right = { address = "0xb", class = "thunar", title = "f", floating = true, fullscreen = 0, pid = 1, tags = {},
                workspace = ws(1), monitor = SCREENS[1], at = { x = 0, y = 0 }, size = { x = 800, y = 600 },
                focus_history_id = 1 }
WINDOWS = { ed, right }
events = {}
r = snap("0xa", 0, 540); ed.at, ed.size = { x = r.x, y = r.y }, { x = r.w, y = r.h }
check("left half, the right one empty: Snap Assist offers it", table.concat(events, "|"):match("agros_assist DP%-1 right 0xa %d+ 51 %d+ %d+") ~= nil, true)
events = {}
r = snap("0xb", 1919, 540); right.at, right.size = { x = r.x, y = r.y }, { x = r.w, y = r.h }
check("right half, the left one taken: no Snap Assist", table.concat(events, "|"):match("agros_assist") == nil, true)
local right_end = right.at.x + right.size.x
dots.window_drag_start("0xa", "resize")
ed.size = { x = ed.size.x + 100, y = ed.size.y }
dots.window_drag_end("0xa", "resize")
r = result()
check("seam: the right one follows", r.x .. "," .. r.w, (right.at.x + 100) .. "," .. (right_end - right.at.x - 100))
-- The right one's app can't go below 700 px wide: dragged 400 px into it, it stops at 700 and the left one is held back
-- to it (as the left one stops at its own smallest, which Hyprland does)
hl.plugin.hyprbars.min_size = function(address) if address == "0xb" then return 700, 200 end return 1, 1 end
ed.size = { x = ed.size.x - 100, y = ed.size.y }
dots.window_drag_start("0xa", "resize")
local was_w = ed.size.x
ed.size = { x = was_w + 400, y = ed.size.y }
dots.window_drag_step("0xa", "resize")
local moved, held = {}, {}
for _, d in ipairs(sent) do
    local w = d[2] and d[2].window
    local who = type(w) == "table" and w.address or w
    if d[1] == "window.resize" then (who == right and moved or who == ed and held or (who == "0xb" and moved or held)).w = d[2].x end
    if d[1] == "window.move" then (who == right and moved or who == ed and held or (who == "0xb" and moved or held)).x = d[2].x end
end
dots.window_drag_end("0xa", "resize"); result()
check("seam at the neighbour's smallest: its width", moved.w, 700)
check("seam at the neighbour's smallest: the left one held back", held.w, right_end - 700 - 12 - ed.at.x)
hl.plugin.hyprbars.min_size = nil
-- Always within reach: let go with its title bar above the top border (40 px reserved), it comes down below it; mostly
-- off the left edge, 150 px of it stays in (no screen to the left); a screen that shrinks re-fits the snapped one
local free = { address = "0xc", class = "org.gnome.Calculator", title = "c", floating = true, fullscreen = 0, pid = 1,
               tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 500, y = 20 }, size = { x = 800, y = 600 },
               focus_history_id = 2 }
WINDOWS = { free, ed, right }
r = snap("0xc", 900, 500)
check("dropped above the top: below it", r.y, 40 + bar)
free.at = { x = -700, y = 300 }
r = snap("0xc", 50, 500)
check("dropped off the left: 150 px in", r.x, 150 - 800)
local was = SCREENS[1].width
SCREENS[1].width = 1600
dots.refit_maximised()
r = result()
check("screen shrunk: the left one fits its half", r.w, math.floor((1600 - 22 - 12) / 2))
SCREENS[1].width = was
-- A pair resized off halves (1200 | 686 of 1898) keeps its split when the screen shrinks: the seam's middle in
-- proportion, the gap the same, the outer edges on the border
dots.refit_maximised(); result()
ed.at, ed.size = { x = 11, y = 51 + bar }, { x = 1200, y = a.h - bar }
right.at, right.size = { x = 1223, y = 51 + bar }, { x = 686, y = a.h - bar }
SCREENS[1].width = 1600
dots.refit_maximised()
local fit = {}
for _, d in ipairs(sent) do
    local w = d[2] and d[2].window
    local who = type(w) == "table" and w.address or w
    if who and d[1] == "window.resize" then fit[who] = fit[who] or {}; fit[who].w = d[2].x end
    if who and d[1] == "window.move" then fit[who] = fit[who] or {}; fit[who].x = d[2].x end
end
sent = {}
SCREENS[1].width = was
check("screen shrunk: a resized pair keeps its split", (fit["0xa"] and fit["0xa"].w) .. "," .. (fit["0xb"] and fit["0xb"].x) .. ","
    .. (fit["0xb"] and fit["0xb"].x + fit["0xb"].w), "997,1020,1589")
check("screen shrunk: the free part's note replaced", areas(ed), "snaparea_DP-1_11_51_" .. (1600 - 22) .. "_" .. a.h .. "_12_" .. bar)
-- Its workspace moved to the other screen (Hyprland moves its windows by the screens' offset only): placed in its zone
-- there, not scaled from the first screen's free part
ed.monitor = SCREENS[2]
dots.refit_maximised()
local moved_ed
for _, d in ipairs(sent) do
    local w = d[2] and d[2].window
    if d[1] == "window.move" and (w == ed or w == "0xa" or (type(w) == "table" and w.address == "0xa")) then moved_ed = d[2].x end
end
sent = {}
ed.monitor = SCREENS[1]
check("its workspace on the other screen: into its zone there", moved_ed ~= nil and moved_ed >= SCREENS[2].x, true)
check("its workspace on the other screen: that screen's free part noted", areas(ed):match("^snaparea_HDMI%-A%-1_[%d_]+$") ~= nil, true)
-- The second screen back beside the first: its right edge isn't a snap edge (the pointer goes on across there)
SCREENS[2].x = 1920
free.tags = {}
free.at = { x = 1000, y = 300 }
r = snap("0xc", 1919, 540)
check("the edge toward another screen: no snap", r.tag == nil and tags(free) == "", true)
-- Off the right edge with the second screen beyond it: left there (it reaches across)
free.at = { x = 1880, y = 300 }
r = snap("0xc", 1000, 500)
check("off the edge, a screen beyond: left there", r.x, nil)
-- ...and the same toward a screen on the left, above and below (the second one is 1152 x 2048 in its turned units): its
-- edge no snap zone, a window reaching across left there
local was_x, was_y, was_gap = SCREENS[2].x, SCREENS[2].y, dots.screen_gap
for _, c in ipairs({ { "left", -1152, 0, { 0, 540 }, { -700, 300 } }, { "above", 0, -2048, { 960, 0 }, { 500, -400 } },
                     { "below", 0, 1080, { 100, 1079 }, { 500, 1040 } },
                     -- (monitors.lua's 64 px gap between screens, which crossing.lua takes the pointer over: still beyond)
                     { "right, across the gap", 1984, 0, { 1919, 540 }, { 1880, 300 }, 64 } }) do
    SCREENS[2].x, SCREENS[2].y, dots.screen_gap = c[2], c[3], c[6]
    free.tags, free.at = {}, { x = 1000, y = 300 }
    r = snap("0xc", c[4][1], c[4][2])
    check("the edge toward a screen " .. c[1] .. ": no snap", r.tag == nil and tags(free) == "", true)
    free.at = { x = c[5][1], y = c[5][2] }
    r = snap("0xc", 1000, 500)
    check("off the edge toward a screen " .. c[1] .. ": left there", (r.x or "") .. (r.y or ""), "")
end
SCREENS[2].x, SCREENS[2].y, dots.screen_gap = was_x, was_y, was_gap
-- Each window's box as dispatched (address -> x, y, w, h), the dispatches then cleared
local function placed()
    local p = {}
    for _, d in ipairs(sent) do
        local w = d[2] and d[2].window
        local who = type(w) == "table" and w.address or w
        if who and (d[1] == "window.resize" or d[1] == "window.move") then
            p[who] = p[who] or {}
            if d[1] == "window.resize" then p[who].w, p[who].h = d[2].x, d[2].y else p[who].x, p[who].y = d[2].x, d[2].y end
        end
    end
    sent = {}
    return p
end
local function at(w, b) w.at, w.size = { x = b.x, y = b.y }, { x = b.w, y = b.h } end
local function snapped(w, x, y)
    w.tags = {}
    hl.get_cursor_pos = function() return { x = x, y = y } end
    dots.window_drag_start(w.address, "move"); dots.window_drag_end(w.address, "move")
    at(w, placed()[w.address])
end
-- Quarters: the top left one resized against a right half moves the bottom left one's edge on the same seam too; the
-- top right one resized down moves the bottom right one's top (a seam across)
local tl = { address = "0x21", class = "a", title = "a", floating = true, fullscreen = 0, pid = 1, tags = {}, workspace = ws(1),
             monitor = SCREENS[1], at = { x = 300, y = 300 }, size = { x = 600, y = 400 }, focus_history_id = 5 }
local bl, rh, tr, br = {}, {}, {}, {}
for k, v in pairs(tl) do bl[k], rh[k], tr[k], br[k] = v, v, v, v end
bl.address, rh.address, tr.address, br.address = "0x22", "0x23", "0x24", "0x25"
WINDOWS = { tl, bl, rh }
SCREENS[2].x = 5000
snapped(tl, 0, 0); snapped(bl, 0, 1079); snapped(rh, 1919, 540)
local bl_w = bl.size.x
dots.window_drag_start("0x21", "resize")
tl.size = { x = tl.size.x + 100, y = tl.size.y }
dots.window_drag_step("0x21", "resize")
local p = placed()
dots.window_drag_end("0x21", "resize"); placed()
check("quarters: the right half follows", p["0x23"] and p["0x23"].x, rh.at.x + 100)
check("quarters: the bottom left one along the seam", p["0x22"] and p["0x22"].w, bl_w + 100)
check("quarters: nothing moved for nothing", p["0x21"], nil)
WINDOWS = { tr, br }
snapped(tr, 1919, 0); snapped(br, 1919, 1079)
dots.window_drag_start("0x24", "resize")
tr.size = { x = tr.size.x, y = tr.size.y + 50 }
dots.window_drag_step("0x24", "resize")
p = placed()
dots.window_drag_end("0x24", "resize"); placed()
check("seam across: the bottom one's top follows", p["0x25"] and (p["0x25"].y .. "," .. p["0x25"].h), (br.at.y + 50) .. "," .. (br.size.y - 50))
-- Four quarters: the top left one widened, the whole vertical seam moves (the bottom row's too)
local q = {}
for k, addr in ipairs({ "0x31", "0x32", "0x33", "0x34" }) do
    q[k] = {}
    for f, v in pairs(tl) do q[k][f] = v end
    q[k].address = addr
end
WINDOWS = q
snapped(q[1], 0, 0); snapped(q[2], 1919, 0); snapped(q[3], 0, 1079); snapped(q[4], 1919, 1079)
dots.window_drag_start("0x31", "resize")
q[1].size = { x = q[1].size.x + 100, y = q[1].size.y }
dots.window_drag_step("0x31", "resize")
p = placed()
dots.window_drag_end("0x31", "resize"); placed()
check("four quarters: the seam moves whole", table.concat({ p["0x32"] and p["0x32"].x or "-", p["0x33"] and p["0x33"].w or "-",
    p["0x34"] and p["0x34"].x or "-" }, ","), (q[2].at.x + 100) .. "," .. (q[3].size.x + 100) .. "," .. (q[4].at.x + 100))
SCREENS[2].x = 1920
-- Let go at the second screen's top edge, most of the window still on the first: maximised on the second (the
-- preview's), onto its workspace
local far = { address = "0x26", class = "a", title = "a", floating = true, fullscreen = 0, pid = 1, tags = {}, workspace = ws(1),
              monitor = SCREENS[1], at = { x = 1000, y = 300 }, size = { x = 800, y = 600 }, focus_history_id = 6 }
WINDOWS = { far }
FOCUS = 2
r = snap("0x26", 2400, 0)
FOCUS = 1
check("let go on the other screen: maximised there", r.tag == "+maximised" and r.x >= 1920, true)
check("let go on the other screen: its workspace", far.workspace.id, 11)
-- Snapped, then maximised (the button): no longer snapped; restored, its next drag keeps its size (not the one it had
-- before it snapped)
far.workspace, far.monitor, far.at = ws(1), SCREENS[1], { x = 1000, y = 300 }
snapped(far, 0, 540)
dots.maximise_window(far); far.tags = { "maximised" }
check("maximised: no longer snapped", tostring(far.tags[2]), "nil")
dots.maximise_window(far); far.tags = {}; result()
dots.window_drag_start("0x26", "move")
check("restored, then dragged: its size kept", result().w, nil)
dots.window_drag_end("0x26", "move"); result()
-- A drag's end the plugin saw no start of (or after a reload mid-drag): Caelestia's panels and the preview let go of
events = {}
dots.window_drag_end("", "")
check("a lone drag end: dragging over", table.concat(events, "|"), "agros_drag 0")
events = {}
dots.window_drag_end("0x26", "move"); result()
check("a lone move end: the preview gone", table.concat(events, "|"), "agros_drag 0|agros_snap none")
-- A popup (opens floating) keeps its own size; one wider than the screen is shrunk to its free part, in the middle
local pop = { address = "0x27", class = "xdg-desktop-portal-gtk", title = "Open With…", floating = true, fullscreen = 0,
              pid = 1, tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = 760, y = 400 },
              size = { x = 400, y = 200 }, focus_history_id = 7 }
WINDOWS = { pop }
sent = {}
for _, fn in ipairs(handlers["window.open"] or {}) do fn(pop) end
check("a popup: its own size", result().w, nil)
pop.at, pop.size = { x = -540, y = 400 }, { x = 3000, y = 200 }
for _, fn in ipairs(handlers["window.open"] or {}) do fn(pop) end
r = result()
check("a wide popup: as wide as the screen's free part, in the middle", r.w .. "," .. r.x .. "," .. r.h, a.w .. "," .. a.x .. ",200")
-- ...and a modal dialog opens floating, so it's one of those (Hyprland's own float needs a parent, which one shown
-- before its window appeared lacks: qView's first-run Welcome was stretched and cascaded behind it)
local modal_floats = false
for _, r in ipairs(WINDOW_RULES) do
    local only_modal = r.match.modal == true and next(r.match, next(r.match)) == nil
    if only_modal and r.float == true then modal_floats = true end
end
check("a modal dialog: floats", modal_floats, true)
-- A window opening tiled (floated as it opens: floating mode), as Hyprland has it by then: the lone tiled window on its
-- workspace, as big as the maximised box when Caelestia's gap round a window alone is the edges' (or less). The
-- standard size, not maximised (every window opened maximised); one the app asked to be maximised (1), maximised
local lone = { address = "0x29", class = "org.gnome.TextEditor", title = "t", floating = false, fullscreen = 0, pid = 1,
               tags = {}, workspace = ws(1), monitor = SCREENS[1], at = { x = a.x, y = a.y }, size = { x = a.w, y = a.h },
               focus_history_id = 9 }
WINDOWS = { lone }
for _, fn in ipairs(handlers["window.open"] or {}) do fn(lone) end
r = result()
check("a window opened as big as the maximised box: not maximised", tostring(r.tag), "nil")
check("a window opened as big as the maximised box: the standard size", r.h, math.floor(1080 * 0.6 + 0.5))
lone.fullscreen = 1
for _, fn in ipairs(handlers["window.open"] or {}) do fn(lone) end
check("a window that asked to open maximised: maximised", result().tag, "+maximised")
-- An X11 menu or tooltip (Caelestia's xwl_popup tag): no title bar counted, and left where its app put it
local menu = { address = "0x28", class = "steam", title = "", floating = true, fullscreen = 0, pid = 1, tags = { "xwl_popup*" },
               workspace = ws(1), monitor = SCREENS[1], at = { x = 100, y = 45 }, size = { x = 300, y = 200 }, focus_history_id = 8 }
check("an X11 menu: no title bar", dots.titlebar_height(menu), 0)
-- Caelestia's Game mode (no gaps, a 1 px border, set at runtime: Hyprland's settings, not Caelestia's variables): a pair
-- snapped before it refitted as it comes on (Hyprland's config.props_refreshed), against the screen's free part and
-- across the new seam (2 px), as the title bar plugin's seams expect; and back as it goes off
local gl = { address = "0x29", class = "thunar", title = "g", floating = true, fullscreen = 0, pid = 1, tags = {},
             workspace = ws(1), monitor = SCREENS[1], at = { x = 500, y = 400 }, size = { x = 800, y = 600 }, focus_history_id = 9 }
local gr = { address = "0x2a", class = "thunar", title = "h", floating = true, fullscreen = 0, pid = 1, tags = {},
             workspace = ws(1), monitor = SCREENS[1], at = { x = 500, y = 400 }, size = { x = 800, y = 600 }, focus_history_id = 9 }
WINDOWS, SCREENS[2].x = { gl, gr }, 5000
snapped(gl, 0, 540); snapped(gr, 1919, 540)
check("before Game mode: a 12 px seam", gr.at.x - (gl.at.x + gl.size.x), 12)
local function refit()
    fire("config.props_refreshed", true)
    local p = placed()
    for _, w in ipairs({ gl, gr }) do
        local b = p[w.address] or {}
        w.at = { x = b.x or w.at.x, y = b.y or w.at.y }; w.size = { x = b.w or w.size.x, y = b.h or w.size.y }
    end
end
CONFIG["general.gaps_in"], CONFIG["general.gaps_out"] = { top = 0, right = 0, bottom = 0, left = 0 }, { top = 0, right = 0, bottom = 0, left = 0 }
CONFIG["general.border_size"] = 1
refit()
check("Game mode on: the pair against the free part", gl.at.x .. "," .. gl.at.y .. "," .. (gr.at.x + gr.size.x), "1," .. (40 + 1 + bar) .. ",1919")
check("Game mode on: a 2 px seam", gr.at.x - (gl.at.x + gl.size.x), 2)
-- (snapped during it: the right half across the 2 px seam)
gr.tags = {}
snapped(gr, 1919, 540)
check("Game mode: snapped right across its seam", gr.at.x, 1 + (1918 - 2) / 2 + 2)
CONFIG["general.gaps_in"], CONFIG["general.gaps_out"], CONFIG["general.border_size"] = nil, nil, nil
refit()
check("Game mode off: the 12 px seam back", gr.at.x - (gl.at.x + gl.size.x) .. "," .. gl.at.x, "12,11")
-- A pair split off halves, Game mode on and off ten times (each reload with it on is a round trip), on a screen whose
-- scale Hyprland gives as a float (its size in those units a hair off whole): the split where it was, not creeping a
-- pixel a time (each placed box rounded, then worked out again from)
local was_scale = SCREENS[1].scale
SCREENS[1].scale = 1920 / 1919.99998
gl.size.x = 1200 - gl.at.x; gr.at.x = 1200 + 12; gr.size.x = 1909 - gr.at.x
for _ = 1, 10 do
    CONFIG["general.gaps_in"], CONFIG["general.gaps_out"] = { top = 0, right = 0, bottom = 0, left = 0 }, { top = 0, right = 0, bottom = 0, left = 0 }
    CONFIG["general.border_size"] = 1
    refit()
    CONFIG["general.gaps_in"], CONFIG["general.gaps_out"], CONFIG["general.border_size"] = nil, nil, nil
    refit()
end
check("ten Game mode round trips: the split kept", (gl.at.x + gl.size.x) .. "," .. gr.at.x, "1200,1212")
SCREENS[1].scale = was_scale
-- A screen an odd number of pixels wide (its halves on half pixels): the window snapped right ends on the free part's
-- edge (its edges rounded, not its size), and the preview showed the box it went to, to the pixel
local was_width = SCREENS[1].width
SCREENS[1].width = 1921
events = {}
gr.tags = {}
snapped(gr, 1920, 540)
local shown
for _, e in ipairs(events) do if e:match("^agros_snap DP") then shown = e end end
check("an odd width: the right half ends on the free part's edge", gr.at.x + gr.size.x, 1921 - 11)
check("an odd width: the preview where it went", shown,
    string.format("agros_snap DP-1 %d %d %d %d", gr.at.x, gr.at.y - bar, gr.size.x, gr.size.y + bar))
SCREENS[1].width = was_width
gr.tags = {}
snapped(gr, 1919, 540)
-- Title bars turned off (the Settings app): the snapped pair fits the free part without them, its top there; and back
local titlebar_height = dots.titlebar_height
dots.titlebar_height = nil
refit()
check("title bars off: up to the free part's top, as tall", gl.at.y .. "," .. gl.size.y, "51," .. a.h)
dots.titlebar_height = titlebar_height
refit()
check("title bars on: below its bar again", gl.at.y .. "," .. gl.size.y, (51 + bar) .. "," .. (a.h - bar))
-- Only the maximised and snapped ones: a maximised one already at its box, a floating one off the screen's edge and an
-- X11 menu mostly off the left edge are left where they are
local mxd = { address = "0x2b", class = "thunar", title = "x", floating = true, fullscreen = 0, pid = 1, tags = { "maximised" },
              workspace = ws(1), monitor = SCREENS[1], at = { x = 11, y = 51 + bar }, size = { x = 1898, y = a.h - bar },
              focus_history_id = 9 }
local off = { address = "0x2c", class = "foot", title = "o", floating = true, fullscreen = 0, pid = 1, tags = {},
              workspace = ws(1), monitor = SCREENS[1], at = { x = -700, y = 300 }, size = { x = 800, y = 600 }, focus_history_id = 9 }
local xmenu = { address = "0x2d", class = "steam", title = "", floating = true, fullscreen = 0, pid = 1, tags = { "xwl_popup*" },
                workspace = ws(1), monitor = SCREENS[1], at = { x = -350, y = 980 }, size = { x = 400, y = 100 }, focus_history_id = 9 }
WINDOWS = { gl, gr, mxd, off, xmenu }
fire("config.props_refreshed", true)
local p = placed()
check("a refresh: nothing moved that was in place", (p["0x2b"] and "max" or "") .. (p["0x2c"] and "off" or "") .. (p["0x2d"] and "menu" or "")
    .. (p["0x29"] and "l" or "") .. (p["0x2a"] and "r" or ""), "")
mxd.size = { x = 1500, y = 700 }
fire("config.props_refreshed", true)
p = placed()
check("a refresh: a maximised one off its box filled again", p["0x2b"] and p["0x2b"].w, 1898)
dots.refit_window(xmenu)
check("an X11 menu never moved into reach", placed()["0x2d"], nil)
-- A burst of events (a layer opened and closed, a setting made; Caelestia's bar's space changed, its call): one refit,
-- a second after the last (the timer set again by each), then as before
HOLD_TIMERS, HELD_TIMERS, TIMER_SETS = true, {}, {}
mxd.size = { x = 1500, y = 700 }
fire("layer.opened"); fire("layer.closed"); fire("config.props_refreshed", true); dots.refit_placed_soon()
check("a burst: one timer, set again by each, a second", #HELD_TIMERS .. ":" .. table.concat(TIMER_SETS, ","), "1:1000,1000,1000,1000")
check("a burst: nothing moved before it settles", placed()["0x2b"], nil)
HELD_TIMERS[1]()
p = placed()
check("a burst: refitted once it settles", p["0x2b"] and p["0x2b"].w, 1898)
HELD_TIMERS, TIMER_SETS = {}, {}
fire("layer.opened")
check("after it: a new timer", #HELD_TIMERS, 1)
HOLD_TIMERS, HELD_TIMERS = false, {}
WINDOWS = { gl, gr }
dots.window_drag_start("0x29", "move"); dots.window_drag_end("0x29", "move"); result()
SCREENS[2].x = 1920
-- The title bar counted (titlebar_height) exactly where the plugin's rules give one (hyprbars:no_bar): a store
-- launcher under Proton (steam_app_default, Caelestia's game tag, yet not a game to dots.is_game) included
local function rx(pat, str)
    local alts = pat:match("^%^%((.*)%)%$$")
    if alts then
        for alt in (alts .. "|"):gmatch("(.-)|") do if str == alt:gsub("\\(.)", "%1") then return true end end
        return false
    end
    return str:match((pat:gsub("\\d", "%%d"):gsub("\\%.", "%%."))) ~= nil
end
local function no_bar(w)
    for _, r in ipairs(WINDOW_RULES) do
        if r["hyprbars:no_bar"] then
            local m, hit = r.match, true
            if m.float ~= nil and w.floating ~= m.float then hit = false end
            if m.fullscreen ~= nil and (w.fullscreen ~= 0) ~= m.fullscreen then hit = false end
            if m.class and not rx(m.class, w.class) then hit = false end
            if m.tag then
                local has = false
                for _, t in ipairs(w.tags) do if t == m.tag or t == m.tag .. "*" then has = true end end
                hit = hit and has
            end
            if hit then return true end
        end
    end
    return false
end
for _, w in ipairs({
    { class = "steam_app_default", tags = { "game" } }, { class = "steam_app_2357570", tags = {} },
    { class = "SomeNativeGame", tags = { "game*" } }, { class = "thunar", tags = {} }, { class = "steam", tags = {} },
    { class = "proton.vpn.app.gtk", tags = {} }, { class = "wine", tags = { "xwl_popup*" } },
    { class = "thunar", tags = {}, fullscreen = 2 }, { class = "thunar", tags = {}, floating = false },
}) do
    w.floating = w.floating ~= false; w.fullscreen = w.fullscreen or 0
    check("title bar counted where the plugin draws one (" .. w.class .. " " .. table.concat(w.tags, ",") .. ")",
        dots.titlebar_height(w) == 0, no_bar(w))
end
for _, fn in ipairs(handlers["window.open"] or {}) do fn(menu) end
check("an X11 menu: left where it is", result().x, nil)
hl.dispatch = hdispatch
for _, e in ipairs(config_errors) do error("config error " .. e, 0) end
L
out=$(cd "$t" && HOME=$t/home PLUGIN=1 XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua drag.lua stub.lua 2>&1)     || fail "window drags: $out"
# The title bar's buttons and double click act on their own window, as the patched plugin names it: one gone by the
# time the command runs (a second click on close as a slow app shut) leaves the rest alone, not the focused window
# closed in its place; the focused one only with the AUR plugin, which leaves "{address}" as it is
cat >"$t/bar.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local commands, config = {}, hl.config
hl.plugin.hyprbars.add_button = function(b) commands[#commands + 1] = b.action end
hl.config = function(c)
    config(c)
    local bars = type(c.plugin) == "table" and c.plugin.hyprbars
    if bars and bars.on_double_click then commands[#commands + 1] = bars.on_double_click end
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
local acted, dispatch = {}, hl.dispatch
hl.dispatch = function(d)
    local a = d and d[2] or {}
    local w = type(a.window) == "string" and hl.get_window(a.window) or a.window
    if type(w) == "table" then acted[#acted + 1] = d[1] .. " " .. w.address end
    return dispatch(d)
end
ACTIVE = WINDOWS[1]
for _, cmd in ipairs(commands) do
    local code = cmd:match("^hyprctl eval '(.*)'$")
    assert(code, "not a hyprctl eval: " .. cmd)
    for _, case in ipairs({ { "0xdead", "" }, { "0x2", "0x2" }, { "{address}", "0x1" } }) do
        acted = {}
        assert(load((code:gsub("{address}", case[1]))))()
        local on = {}
        for _, a in ipairs(acted) do on[a:match("(%S+)$")] = true end
        local want = case[2] == "" and next(on) == nil or case[2] ~= "" and on[case[2]] and not on[case[2] == "0x1" and "0x2" or "0x1"]
        if not want then
            io.write("FAIL ", cmd, " with ", case[1], ": ", table.concat(acted, ", "), "\n")
        end
    end
end
io.write("bar commands ", #commands, "\n")
L
out=$(cd "$t" && HOME=$t/home PLUGIN=1 XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua bar.lua stub.lua 2>&1) || fail "title bar commands: $out"
grep -q '^FAIL' <<<"$out" && fail "a title bar command acted on another window: $(grep '^FAIL' <<<"$out")"
grep -qx 'bar commands 4' <<<"$out" || fail "the title bar's commands weren't all checked: $out"
# Super+drag off while the switcher is open (its Super+click on a workspace), back as it closes; and back a moment
# after Super or Alt is let go (its pick, which closes it) even when the switcher never says it closed: it died or hung
# open (one Quickshell restarted after a crash comes back closed), and Super+drag was off until the next config reload
cat >"$t/switcher.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
local function run_timers() local q = HELD_TIMERS; HELD_TIMERS = {}; for _, fn in ipairs(q) do fn() end end
local function drag() return tostring(#(BIND_ACTIONS["SUPER + mouse:272"] or {})) end
HOLD_TIMERS = true
dots.switcher_open(true); io.write("open ", drag(), "\n")
fire("input.keyboard.key", 133, 0, 1); fire("input.keyboard.key", 133, 0, 0)
dots.switcher_open(false); run_timers(); io.write("closed ", drag(), "\n")
dots.switcher_open(true); fire("input.keyboard.key", 64, 0, 0); io.write("let go, not yet ", drag(), "\n")
run_timers(); io.write("died open ", drag(), "\n")
fire("input.keyboard.key", 133, 0, 0); run_timers(); io.write("let go, closed ", drag(), "\n")
L
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua switcher.lua stub.lua 2>&1) ||
    fail "switcher: $out"
[[ $(grep -E '^(open|closed|let go|died)' <<<"$out" | paste -sd'|') == \
    "open 0|closed 1|let go, not yet 0|died open 1|let go, closed 1" ]] ||
    fail "Super+drag around the switcher: $(grep -E '^(open|closed|let go|died)' <<<"$out" | paste -sd'|')"

# One user module erroring (a Hyprland update renamed something it uses): the others still load, and it's still an
# error for Hyprland to show
cp "$t/home/.config/caelestia/user/workspaces.lua" "$t/workspaces.lua.bak"
printf 'error("renamed API")\n' >"$t/home/.config/caelestia/user/workspaces.lua"
cat >"$t/broken.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
local ok, err = pcall(require, "hypr-user")
io.write("loaded ", tostring(ok), " ", tostring(err):gsub("\n", " "), "\n")
for _, b in ipairs(binds) do io.write("bind ", b, "\n") end
L
# (a key of keys.lua's, loaded after workspaces.lua, bound from settings.lua)
printf '%s\n' 'return { ["keys.restart_shell"] = { "CTRL + SUPER + ALT + R" } }' >"$t/home/.config/dots/settings.lua"
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua broken.lua stub.lua 2>&1)
grep -q '^loaded false .*user.workspaces.*renamed API' <<<"$out" || fail "a broken user module wasn't reported: $(head -3 <<<"$out")"
grep -qx "bind CTRL + SUPER + ALT + R" <<<"$out" || fail "a broken user module took the ones after it down: $(head -5 <<<"$out")"
cp "$t/workspaces.lua.bak" "$t/home/.config/caelestia/user/workspaces.lua"
# A game's splash (its first window, small) holds its other windows back; a first window filling a scaled screen (a
# window's size is in the screen's units, its mode over its scale) isn't one: its next window shown, not held
cat >"$t/splash.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
local m = { name = "DP-1", x = 0, y = 0, width = 3840, height = 2160, scale = 2, transform = 0, active_workspace = ws(1),
            reserved = { top = 0, bottom = 0, left = 0, right = 0 } }
SCREENS, FOCUS = { m }, 1
local function game(address, w, h)
    return { address = address, class = "steam_app_1", title = "Game", floating = true, fullscreen = 0, pid = 4242,
             tags = { "game*" }, workspace = ws(1), monitor = m, at = { x = 0, y = 0 }, size = { x = w, y = h } }
end
local function open(w)
    WINDOWS[#WINDOWS + 1] = w
    for _, fn in ipairs(handlers["window.open"] or {}) do fn(w) end
end
for _, size in ipairs({ { 1920, 1080, "full" }, { 600, 300, "small" } }) do
    WINDOWS = {}
    open(game("0xa" .. size[3], size[1], size[2])); local next = game("0xb" .. size[3], 1920, 1080); open(next)
    io.write(size[3], " first window: the next ", next.workspace.name, "\n")
    dots.splash_release(4242)
end
L
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua splash.lua stub.lua 2>&1) || fail "splash: $out"
grep -qx "full first window: the next 1" <<<"$out" || fail "a game's first window filling a scaled screen taken for a splash: $out"
grep -qx "small first window: the next special:splash" <<<"$out" || fail "a game's small first window not taken for a splash: $out"

# On NVIDIA (its nvidia_drm module loaded) Wayland's commit timing is off (its driver's frame target after a pause froze
# games); elsewhere Hyprland's own
cat >"$t/render.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local timing, config = "unset", hl.config
hl.config = function(c)
    config(c)
    if type(c.render) == "table" and c.render.commit_timing_enabled ~= nil then timing = tostring(c.render.commit_timing_enabled) end
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
io.write(timing, "\n")
L
render_load() { (cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test SYSFS=$1 lua render.lua stub.lua 2>&1 | tail -1); }
mkdir -p "$t/sys-nv/module/nvidia_drm" "$t/sys-none/module"; echo live >"$t/sys-nv/module/nvidia_drm/initstate"
[[ $(render_load "$t/sys-nv") == false && $(render_load "$t/sys-none") == unset ]] ||
    fail "commit timing not off on NVIDIA only: $(render_load "$t/sys-nv") / $(render_load "$t/sys-none")"

# Focus on a click (floating mode's default): a closed window's focus goes to the one used before it (focus_on_close 2,
# "mru"), not to the one under the pointer (Caelestia's 1: none over the desktop, and Super+Q then did nothing); on
# hover (the Settings app's choice, or tiling), as Caelestia has it
cat >"$t/focus.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local input, config = {}, hl.config
hl.config = function(c)
    config(c)
    for k, v in pairs(c.input or {}) do input[k] = v end
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
require("hypr-user")
io.write(tostring(input.follow_mouse), " ", tostring(input.focus_on_close), "\n")
L
focus_load() {
    rm -f "$t/home/.config/dots/settings.lua" "$t/home/.local/state/window-mode"
    [[ -z $1 ]] || printf '%s\n' "$1" >"$t/home/.config/dots/settings.lua"
    [[ -z $2 ]] || echo "$2" >"$t/home/.local/state/window-mode"
    (cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua focus.lua stub.lua 2>&1 | tail -1)
}
[[ $(focus_load 'return { ["windows.focus"] = "click" }' '') == "2 2" ]] ||
    fail "focus on a click: a closed window's focus not to the one used before: $(focus_load 'return { ["windows.focus"] = "click" }' '')"
[[ $(focus_load 'return { ["windows.focus"] = "hover" }' '') == "1 1" ]] ||
    fail "focus on hover: not as Caelestia has it: $(focus_load 'return { ["windows.focus"] = "hover" }' '')"
# (none chosen: on hover, the Settings app's default)
[[ $(focus_load '' '') == "1 1" ]] || fail "focus not on hover by default: $(focus_load '' '')"
[[ $(focus_load '' tiling) == "1 1" ]] || fail "tiling: not as Caelestia has it: $(focus_load '' tiling)"
rm -f "$t/home/.local/state/window-mode"

# VMware's vmw-dmabuf shim (Hyprland's only) taken out of LD_PRELOAD for the apps, wherever it is in the list, the
# session's other preloads kept as they were (no stray ':'); none there: LD_PRELOAD left alone
cat >"$t/preload.lua" <<'L'
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
dofile(arg[1])
local getenv, shim = os.getenv, "/usr/lib/agros/vmw-dmabuf.so"
for _, c in ipairs({ { shim, "" }, { shim .. ":/a.so", "/a.so" }, { "/a.so:" .. shim, "/a.so" },
                     { "/a.so:" .. shim .. ":/b.so", "/a.so:/b.so" }, { "/a.so", nil }, { nil, nil } }) do
    os.getenv = function(k) if k == "LD_PRELOAD" then return c[1] end return getenv(k) end
    ENV, package.loaded["hypr-vars"] = {}, nil
    require("hypr-vars")
    if ENV.LD_PRELOAD ~= c[2] then error(tostring(c[1]) .. ": " .. tostring(ENV.LD_PRELOAD) .. ", not " .. tostring(c[2]), 0) end
end
L
out=$(cd "$t" && HOME=$t/home lua preload.lua stub.lua 2>&1) || fail "LD_PRELOAD without the shim: $out"

# In VMware without the shim, the apps on the CPU: the two variables in the user's systemd and D-Bus environments as
# the config loads (before Hyprland starts anything), and Hyprland's own children's once it's up. With the shim (in
# Hyprland's maps), outside VMware, in a check of the config or a reload (Hyprland has them already): neither
mkdir -p "$t/sys/module"
cat >"$t/vmware.lua" <<'L'
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
dofile(arg[1])
local open, getenv = io.open, os.getenv
-- (VMware by its driver's folder in sysfs, as the login screen and the shim's drop-in tell it)
local function run(vmware, shim, env)
    local module = getenv("SYSFS") .. "/module/vmwgfx"
    if vmware then os.execute("mkdir -p '" .. module .. "'") else os.remove(module) end
    io.open = function(p, ...)
        if p == "/proc/self/maps" then MAPS_READ = true end
        if p == "/proc/self/maps" and shim then
            return { read = function() return "7f00 r-xp /usr/lib/agros/vmw-dmabuf.so\n" end, close = function() end }
        end
        return open(p, ...)
    end
    os.getenv = function(k) if env[k] ~= nil then return env[k] end return getenv(k) end
    ENV, SESSION_ENV, handlers, package.loaded["hypr-vars"] = {}, {}, {}, nil
    require("hypr-vars")
    local loaded = #SESSION_ENV
    for _, fn in ipairs(handlers["hyprland.start"] or {}) do fn() end
    return loaded, ENV.LIBGL_ALWAYS_SOFTWARE == "1" and ENV.XWAYLAND_NO_GLAMOR == "1"
end
local function check(name, ok) if not ok then error(name, 0) end end
local loaded, apps = run(true, false, {})
check("VMware without the shim: not in the session's environment as the config loads", loaded == 1
      and SESSION_ENV[1]:find("systemctl --user set-environment LIBGL_ALWAYS_SOFTWARE=1 XWAYLAND_NO_GLAMOR=1", 1, true)
      and SESSION_ENV[1]:find("dbus-update-activation-environment LIBGL_ALWAYS_SOFTWARE=1 XWAYLAND_NO_GLAMOR=1", 1, true))
check("VMware without the shim: not for Hyprland's children", apps)
loaded, apps = run(true, true, {})
check("VMware with the shim: set", loaded == 0 and not apps)
MAPS_READ = false
loaded, apps = run(false, false, {})
check("not VMware: set", loaded == 0 and not apps)
-- (nor Hyprland's maps read there: the config loads again at every reload)
check("not VMware: Hyprland's maps read", not MAPS_READ)
loaded = run(true, false, { DOTS_VERIFY_CONFIG = "1" })
check("a check of the config: put in the session's environment", loaded == 0)
loaded, apps = run(true, false, { LIBGL_ALWAYS_SOFTWARE = "1" })
check("a reload: put in the session's environment again", loaded == 0 and apps)
L
out=$(cd "$t" && HOME=$t/home SYSFS=$t/sys lua vmware.lua stub.lua 2>&1) || fail "the VMware fallback: $out"
# Every setting the config makes (at load and in its handlers, as the runs above played them) in Hyprland's own list of
# them (its Lua stubs; the plugins' own aside): a setting renamed or gone found here, not only at the next login
stubs=/usr/share/hypr/stubs/hl.meta.lua
if [[ -f $stubs ]]; then
    python3 -I - "$stubs" "$t/config-keys" <<'PY' || fail "settings the installed Hyprland doesn't have (above)"
import re, sys
keys, alias = set(), None
for line in open(sys.argv[1]):
    if m := re.match(r"---@alias ([\w.]+)", line):
        alias = m[1]
    elif (m := re.match(r'---\| "([^"]+)"', line)) and alias == "HL.ConfigKey":
        keys.add(m[1])
assert keys, "the stubs' layout changed: this check needs updating"
bad = set()
for path in open(sys.argv[2]).read().split():
    parts = path.split(".")
    if parts[0] == "plugin" or any(".".join(parts[:i]) in keys for i in range(1, len(parts) + 1)):
        continue
    bad.add(path)
for b in sorted(bad):
    print(f"hl.config: {b}")
sys.exit(1 if bad else 0)
PY
fi
echo "ok hypr-config"
