#!/usr/bin/env bash
# The Hyprland config (hypr-vars.lua, hypr-user.lua and user/*.lua) run by plain Lua against a stand-in for Hyprland's
# hl API, in a throwaway home: every file compiles; the whole config loads with the settings file missing, broken or
# odd, with and without the title bar plugin; the event handlers (windows opening, keys, screens) and the functions
# scripts call don't error; every dots.bind / dots.setting name is in the Settings app's schema and every function in
# the README's Lua API table exists
set -euo pipefail
. "$(dirname "$0")/lib.sh"
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
-- LID: what /proc says of the laptop lid; RELOADED: a dispatched "hyprctl reload"
local plugin = os.getenv("PLUGIN") == "1"
handlers, binds, config_errors, hidden_rules, unset_gestures, WINDOW_RULES = {}, {}, {}, {}, {}, {}
-- CONFIG: what hl.get_config answers (the blur setting window peek turns off and back); HELD_TIMERS: timers queued
-- there while HOLD_TIMERS is on (else run at once); PEEK_TAGS: window peek's tag dispatches, in order
CONFIG, HELD_TIMERS, PEEK_TAGS = { ["decoration.blur.ignore_opacity"] = true }, {}, {}
BIND_ACTIONS, MONITOR_RULES, FOCUS = {}, {}, 1
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
        local blur = type(c) == "table" and c.decoration and c.decoration.blur
        if blur and blur.ignore_opacity ~= nil then CONFIG["decoration.blur.ignore_opacity"] = blur.ignore_opacity end
    end,
    get_config = function(key) return CONFIG[key] end,
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
        if tostring(cmd):find("notify-send", 1, true) then io.write("exec notify-send\n") end
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
            if w then w.workspace = id and ws(id) or { name = a.workspace, special = true } end
            -- (followed unless follow = false: the window's workspace shown)
            if w and id and a.follow ~= false then hl.dispatch(hl.dsp.focus({ workspace = id })) end
        elseif name == "workspace.move" then
            -- (a screen's shown workspace moved away: it shows its own first one)
            for k, m in ipairs(SCREENS) do
                if m.name == a.monitor then m.active_workspace = ws(a.workspace)
                elseif m.active_workspace and m.active_workspace.id == a.workspace then m.active_workspace = ws((k - 1) * 10 + 1) end
            end
        elseif name == "window.tag" then
            -- (window peek's tags added, "+name", or taken off, "-name", as Hyprland's tag dispatcher; others only recorded)
            local w = type(a.window) == "string" and hl.get_window(a.window) or a.window
            local sign, tag = tostring(a.tag):match("^([+-])(.+)$")
            if w and tag and tag:match("^dots%-peek") then
                PEEK_TAGS[#PEEK_TAGS + 1] = w.address .. sign .. tag
                for k = #w.tags, 1, -1 do if w.tags[k] == tag then table.remove(w.tags, k) end end
                if sign == "+" then w.tags[#w.tags + 1] = tag end
            end
        elseif name == "exec_cmd" and tostring(a):find("hyprctl reload", 1, true) then
            RELOADED = true
        end
    end,
    timer = function(fn) if HOLD_TIMERS then HELD_TIMERS[#HELD_TIMERS + 1] = fn else fn() end end,
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
    get_monitors = function() return SCREENS end,
    get_active_monitor = function() return SCREENS[FOCUS] or SCREENS[1] end,
    get_active_workspace = function() return (SCREENS[FOCUS] or SCREENS[1]).active_workspace end,
    get_active_window = function() return ACTIVE or WINDOWS[1] end,
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
-- What scripts call through hyprctl eval (README's Lua API), with the arguments they pass
dots.focus_window("0x3", true); dots.focus_window("0xdead")
dots.focus_app("org.gnome.Nautilus", "Files", true); dots.focus_app(nil, nil, false)
dots.maximise_window(); dots.minimise_window(); dots.refit_maximised(); dots.toggle_window_mode(); dots.toggle_window_mode()
dots.titlebar_drag_start("0x3", "before"); dots.goto_workspace(13); dots.goto_workspace(1)
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
dots.peek("0x1"); io.write("peeked ", peeked(), " blur over opacity ", blur(), "\n")
local made = {}
for i = rules_before + 1, #WINDOW_RULES do
    local r = WINDOW_RULES[i]
    made[#made + 1] = tostring(r.name) .. ":" .. tostring(r.match.tag) .. ":" .. tostring(r.opacity) .. ":" .. tostring(r.opaque)
end
io.write("peek rules ", table.concat(made, ","), "\n")
PEEK_TAGS = {}
dots.peek("0x2"); io.write("peeked then ", peeked(), "\n")
io.write("peek tags then ", table.concat(PEEK_TAGS, ","), "\n")
io.write("peek rules after another peek ", #WINDOW_RULES - rules_before, "\n")
HOLD_TIMERS = true
dots.peek_end(); io.write("peek ending ", peeked(), " blur over opacity ", blur(), "\n")
run_timers(); io.write("peek ended ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek_screen("DP-1", "0x1", "0x5"); io.write("peek screen ", peeked(), "\n")
dots.peek_screen("DP-1"); io.write("peek screen bare ", peeked(), "\n")
-- (an end's clean-up, due after its fade back, left alone by a peek meanwhile)
dots.peek_end(); dots.peek("0x1"); run_timers(); io.write("peek again meanwhile ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek_screen("NOPE-1", "0x1"); run_timers(); io.write("peek of no screen ", peeked(), " blur over opacity ", blur(), "\n")
dots.peek("0xdead"); run_timers(); io.write("peek of no window ", peeked(), "\n")
-- (the blur setting already off in the config: left off)
CONFIG["decoration.blur.ignore_opacity"] = false
dots.peek("0x1"); dots.peek_end(); run_timers(); io.write("peek with the blur setting off ", blur(), "\n")
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
L

# One load: HOME with the given settings.lua (none if empty), the title bar plugin on or off, [one screen]
run_config() {
    rm -f "$t/home/.config/dots/settings.lua"
    [[ -z $1 ]] || printf '%s\n' "$1" >"$t/home/.config/dots/settings.lua"
    (cd "$t" && HOME=$t/home PLUGIN=$2 ONE_SCREEN=${3:-0} DOTS_VERIFY_CONFIG=${VERIFY:-} XDG_CONFIG_HOME=${XCH:-} XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test \
        lua run.lua stub.lua 2>&1)
}
good='return { ["keys.windows_next"] = { "ALT + TAB" }, ["keys.minimise"] = { "SUPER + M", "SUPER + DOWN" },
  ["keys.screenshot"] = {}, ["windows.cascade"] = true, ["windows.titlebars"] = true, ["windows.focus"] = "hover",
  ["startup.lutris"] = true, ["caelestia-keys.kbTerminal"] = { "SUPER + RETURN" }, ["caelestia-keys.kbGoToWs"] = { "ALT" } }'
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
    p "peek of no window "
    p "peek with the blur setting off false"
    # ...by rules made once, at the first peek (after the config's, LibreWolf's opaque one too), that win over opaque ones
    ! grep -q "^peek rule made as the config loads" <<<"$out" || fail "window peek's rules made as the config loads"
    p "peek rules dots-peek:dots-peek:0 override:false,dots-peek-back:dots-peek-back:1 override:false,dots-peek-back-see:dots-peek-back-see:0.95 override:false,dots-peek-back-see-full:dots-peek-back-see:1 override:false"
    p "peek rules after another peek 4"
done
# Every window this config makes opaque tagged dots_opaque too: window peek fades it back to whole, not see-through
# (then a jump to whole once its tag is off)
bad=$(grep -h "opaque = true" "$here"/.config/caelestia/user/*.lua | grep -v "dots_opaque" | grep "window_rule" || true)
[[ -z $bad ]] || fail "opaque without the dots_opaque tag (window peek fades it back see-through): $bad"
# One screen (a HiDPI laptop panel alone): the same config loads with no errors
out=$(run_config "$good" 1 1) || fail "the config failed to load on one screen: $(tail -4 <<<"$out")"
grep -q '^config error' <<<"$out" && fail "config errors on one screen: $(grep '^config error' <<<"$out")"
# Every function of the README's Lua API table is there once the config has loaded
for f in $(grep -E '^\| `[a-z_]+\(' "$here/README.md" | cut -d'|' -f2 | grep -oE '`[a-z_]+\(' | tr -d '`('); do
    grep -qx "function $f" <<<"$out" || fail "dots.$f (README's Lua API) isn't defined"
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
# Its notification that the settings failed to load: not when it's only a check (hypr-config-check: dotfiles-check says it)
out=$(run_config 'return 42' 0)
grep -q "^exec notify-send" <<<"$out" || fail "settings that failed to load not said"
out=$(VERIFY=1 run_config 'return 42' 0)
grep -q "^exec notify-send" <<<"$out" && fail "a notification sent by the config check (DOTS_VERIFY_CONFIG)"
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
-- (a rule set from the switch would do nothing in Hyprland until the next load: the switch reloads, and that load reads
-- the lid)
LID = "state:      open\n"; load(); local rules = #MONITOR_RULES; LID = "state:      closed\n"; press("switch:on:Lid Switch")
check("the lid closing reloads", RELOADED, true); check("rules set from the lid switch", #MONITOR_RULES, rules)
panel.enabled = false; RELOADED = nil; LID = "state:      open\n"; press("switch:off:Lid Switch")
check("the lid opening reloads", RELOADED, true); load()
check("panel at a load with the lid open", last_rule("eDP-1"), nil)
panel.enabled = true; SCREENS = { panel }; LID = "state:      closed\n"; load()
check("panel alone with the lid closed", last_rule("eDP-1"), nil)
-- The other screen unplugged while the panel was off: no rule of its own, so the host file's (mode, scale) turns it on,
-- not one with nothing but "on" replacing it
panel.enabled = false; load()
check("panel off, alone, with the lid closed", last_rule("eDP-1"), nil)
for _, e in ipairs(config_errors) do error("config error " .. e, 0) end
L
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua sync.lua stub.lua 2>&1) \
    || fail "synced screens: $out"
# Window drags: edges resize (Hyprland's resize_on_border on, off while a game is open), and a maximised window dragged stops being maximised:
# moved (any title bar, the plugin's hook), shrunk to the standard size round the pointer; resized, only untagged
cat >"$t/drag.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local general, config = {}, hl.config
hl.config = function(c)
    config(c)
    for k, v in pairs(c.general or {}) do general[k] = v end
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
local game = WINDOWS[2]
fire("window.close", game); WINDOWS = { WINDOWS[1] }
check("edges once the game closed", general.resize_on_border, true)
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
-- The floating/tiling switch, both ways, leaves a pinned window be (picture-in-picture, Capri): tiled, it lost its pin
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
-- An app's minimise request with no window to it (gone by then): nothing, not the focused window minimised instead
fire("window.minimize", nil, true)
check("minimise request with no window", steps(), "")
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
for _, e in ipairs(config_errors) do error("config error " .. e, 0) end
L
out=$(cd "$t" && HOME=$t/home PLUGIN=1 XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua drag.lua stub.lua 2>&1)     || fail "window drags: $out"
# Capri: her key only once she's installed (it would take Shift+Space from other apps), and off over a fullscreen window
cat >"$t/capri.lua" <<'L'
local home = os.getenv("HOME")
package.path = home .. "/.config/caelestia/?.lua;" .. home .. "/.config/hypr/?.lua;" .. package.path
dofile(arg[1])
local blur, config = {}, hl.config
hl.config = function(c)
    config(c)
    for k, v in pairs((c.decoration or {}).blur or {}) do blur[k] = v end
end
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
-- Her key's binds as Hyprland makes them (on or off: set_enabled), and timers run when the test says (later)
local made, timers, bind = {}, {}, hl.bind
hl.bind = function(keys, ...)
    bind(keys, ...)
    local b = { keys = keys, on = true, set_enabled = function(self, on) self.on = on end }
    made[#made + 1] = b
    return b
end
hl.timer = function(fn) timers[#timers + 1] = fn end
require("hypr-user")
io.write("blur ", tostring(blur.size), "\n")
for _, b in ipairs(binds) do io.write("bind ", b, "\n") end
-- Off while the workspace you're on has a fullscreen window (a game kept losing Shift), on again once it's gone: its
-- closing (still there while its close event runs) and focus moving to the other screen
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
-- (hers by its keys: not the last bind made, which a module loaded after apps.lua may add)
local function key()
    for _, b in ipairs(made) do if b.keys == "SHIFT + Space" then return tostring(b.on) end end
    return "none"
end
-- (what an event timed to run just after it: hers are looked at then)
local function settle() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end
local ws = hl.get_active_workspace()
ws.has_fullscreen = true; fire("window.fullscreen", WINDOWS[2]); settle(); io.write("fullscreen ", key(), "\n")
fire("window.close", WINDOWS[2]); ws.has_fullscreen = false
settle()
io.write("closed ", key(), "\n")
ws.has_fullscreen = true; fire("window.fullscreen", WINDOWS[2]); settle(); FOCUS = 2; fire("monitor.focused", SCREENS[2]); settle()
io.write("other screen ", key(), "\n")
-- Off while a game has the focus, borderless (not fullscreen) too; on again once something else has it
FOCUS = 1; ws.has_fullscreen = false
ACTIVE = { address = "0x9", class = "steam_app_2", title = "Borderless", fullscreen = 0, pid = 1, tags = { "game*" },
           workspace = ws, monitor = SCREENS[1] }
fire("window.active", ACTIVE); settle(); io.write("borderless game ", key(), "\n")
ACTIVE = nil; fire("window.active", WINDOWS[1]); settle(); io.write("game unfocused ", key(), "\n")
L
printf '%s\n' 'return { ["keys.capri"] = { "SHIFT + Space" } }' >"$t/home/.config/dots/settings.lua"
capri_load() { (cd "$t" && HOME=$t/home CAPRI_RUN=$1 XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua capri.lua stub.lua 2>&1); }
out=$(capri_load "") || fail "Capri: $out"
grep -qx "bind SHIFT + Space" <<<"$out" && fail "Capri's key bound with her not installed"
mkdir -p "$t/home/.local/share/capri/current"; echo '{}' >"$t/home/.local/share/capri/current/package.json"
out=$(capri_load "") || fail "Capri: $out"
grep -qx "bind SHIFT + Space" <<<"$out" || fail "Capri's key missing with her installed"
grep -qx "fullscreen false" <<<"$out" || fail "Capri's key still bound over a fullscreen window: $out"
grep -qx "closed true" <<<"$out" || fail "Capri's key stayed off after the fullscreen window closed: $out"
grep -qx "other screen true" <<<"$out" || fail "Capri's key stayed off on the other screen: $out"
grep -qx "borderless game false" <<<"$out" || fail "Capri's key still bound over a focused borderless game: $out"
grep -qx "game unfocused true" <<<"$out" || fail "Capri's key stayed off after the game lost the focus: $out"
# Run from a checkout of her code ($CAPRI_RUN, as ~/.local/bin/capri runs it) with no build: her key too. A start
# script where the launcher once looked by itself (~/Projects/run-capri.sh), not named in $CAPRI_RUN: not hers
rm -r "$t/home/.local/share/capri"
mkdir -p "$t/home/Projects"; printf '#!/bin/sh\n' >"$t/home/Projects/run-capri.sh"; chmod +x "$t/home/Projects/run-capri.sh"
out=$(capri_load "") || fail "Capri: $out"
grep -qx "bind SHIFT + Space" <<<"$out" && fail "Capri's key bound for a start script \$CAPRI_RUN doesn't name"
out=$(capri_load "$t/home/Projects/run-capri.sh") || fail "Capri: $out"
grep -qx "bind SHIFT + Space" <<<"$out" || fail "Capri's key missing with \$CAPRI_RUN's start script there"
rm -r "$t/home/Projects"
mkdir -p "$t/home/.local/share/capri/current"; echo '{}' >"$t/home/.local/share/capri/current/package.json"
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
out=$(cd "$t" && HOME=$t/home XDG_RUNTIME_DIR=$t/run HYPRLAND_INSTANCE_SIGNATURE=test lua broken.lua stub.lua 2>&1)
grep -q '^loaded false .*user.workspaces.*renamed API' <<<"$out" || fail "a broken user module wasn't reported: $(head -3 <<<"$out")"
grep -qx "bind SHIFT + Space" <<<"$out" || fail "a broken user module took the ones after it down: $(head -5 <<<"$out")"
cp "$t/workspaces.lua.bak" "$t/home/.config/caelestia/user/workspaces.lua"
echo "ok hypr-config"
