-- Apps: where they open, how they start at login, and their window rules

-- No special workspaces: apps Caelestia sends to its music, communication, todo and system monitor ones
-- (Spotify, Equibop, btop...) open on the normal workspaces (their keys are off in hypr-vars.lua)
for _, tag in ipairs({ "music_player", "communication_app", "todo_app", "system_monitor" }) do
    hl.window_rule({ match = { tag = tag }, workspace = "unset" })
end

-- Apps started at login, each a switch in the Settings app (Startup page: startup.<app>; defaults in its schema: only
-- Lutris, Proton VPN and Capri on)
local function at_login(app, cmd)
    if dots.setting("startup." .. app) then hl.on("hyprland.start", function() hl.exec_cmd(cmd) end) end
end

-- Proton VPN at login (app-launch: in a unit of its own under uwsm, like apps started from the launcher)
-- After keyring-default (desktop.lua) has made "login" the default keyring: started alongside, on a fresh install it
-- could ask for the old keyring's password while that's being moved
at_login("protonvpn", "sh -c '~/.local/bin/keyring-default; exec ~/.local/bin/app-launch protonvpn-app'")

-- Lutris at login, in its tray only (the patched one, ~/.local/bin/lutris), in a unit of its own like apps from the
-- launcher. Store launchers (Steam...) aren't started: they start when a game needs them (Steam through steam-start)
at_login("lutris", "~/.local/bin/app-launch env LUTRIS_START_HIDDEN=1 lutris")
-- Steam's own notification toasts ("friend started playing...") are windows: tag them like its menus, so the dock
-- doesn't show them
hl.window_rule({ match = { class = "steam", title = "notificationtoasts_.*" }, tag = "+xwl_popup" })
-- The Updates and Desktop Settings apps (named after their launcher entries: QS_APP_ID, ~/.local/bin/updates): the
-- float and opaque Caelestia gives Quickshell windows (org.quickshell, its rules.lua). Set as such, not as its "float"
-- and "opaque" tags: a tag only takes effect from rules made before Caelestia's rule for it, which come before this file
hl.window_rule({ match = { class = "^(updates|desktop-settings)$" }, float = true, opaque = true, tag = "+dots_opaque" })
-- LibreWolf opaque too (Caelestia's opacity for every other window left web pages see-through)
-- (both tagged dots_opaque too: window peek, user/windows.lua, fades them back to whole, as they are)
hl.window_rule({ match = { class = "^(librewolf)$" }, opaque = true, tag = "+dots_opaque" })
-- Games: Caelestia tags them "game" by class (Proton's steam_app_<id>, Lutris's steam_app_default, gamescope) and gives
-- that tag its rules (tearing allowed, no idle, opaque). Native Linux Steam games keep their own class: tagged here by
-- the SteamGameId Steam puts in their environment (as game-focus finds them), which a window rule can't see
local function proc(pid, file)
    local f = pid and io.open("/proc/" .. pid .. "/" .. file, "rb")
    local text = f and f:read("a")
    if f then f:close() end
    return text
end
-- Only a program from Steam's games folder (Proton's with Windows "\"; one started as ./Game: by its file): one a game
-- started (a browser opening a link) inherits SteamGameId too. Once per process: Hyprland stops a window.open handler
-- after 50 ms, and a game's windows come in bursts (false: not a game)
local function read_game_id(pid)
    local env = proc(pid, "environ")
    local id = env and ("\0" .. env):match("%zSteamGameId=(%d+)")
    if not id or id == "0" then return nil end
    if (proc(pid, "cmdline") or ""):find("steamapps[/\\]common[/\\]") then return id end
    -- Started as ./Game from its folder: by its file
    local exe = io.popen("readlink /proc/" .. math.tointeger(pid) .. "/exe")
    local path = exe and exe:read("l") or ""
    if exe then exe:close() end
    return path:find("/steamapps/common/", 1, true) and id or nil
end
-- (by pid and its start time: a pid used again later is another process)
local game_ids = {}
local function steam_game_id(pid)
    local stat = proc(pid, "stat")
    if not stat then return nil end
    -- (after the last ")": the name before it may hold ") ")
    local key = pid .. ":" .. (stat:match("^.*%) %S+" .. (" %S+"):rep(18) .. " (%d+)") or "")
    if game_ids[key] == nil then game_ids[key] = read_game_id(pid) or false end
    return game_ids[key] or nil
end
local function is_game(win)
    local tags = type(win.tags) == "table" and table.concat(win.tags, " ") or (win.tags or "")
    return (" " .. tags .. " "):find("[ ]game%*?[ ]") ~= nil
end
-- dots.is_game: any game (Proton, Lutris/umu, gamescope, native Steam), also a native one before the tag below is on
-- (windows.lua and titlebars.lua's own window.open handlers can run first)
function dots.is_game(win) return win ~= nil and (is_game(win) or steam_game_id(win.pid) ~= nil) end
hl.on("window.open", function(win)
    if win and not is_game(win) and steam_game_id(win.pid) then
        hl.dispatch(hl.dsp.window.tag({ tag = "+game", window = win }))
    end
end)
-- Edge resizing (windows.lua) off while a game is open: Hyprland grows every floating window on a shown workspace by
-- 16 px for it, and a game, borderless over the whole screen but not fullscreen, then took a click on the next screen
-- beside it, or in a screen corner (its rounded corner: an RTS's camera scroll), as the start of a resize. On again
-- once the last one closes. Counted at every load (it sets this back on), as windows open and close (the closing one
-- still mapped then), and as one is tagged a game later (the tag above, a class rule matching after a class change)
local edges = true
local function game_edges(closing)
    local game = false
    for _, w in ipairs(hl.get_windows({ mapped = true }) or {}) do
        if w.address ~= closing and dots.is_game(w) then game = true break end
    end
    if edges == not game then return end
    edges = not game
    hl.config({ general = { resize_on_border = edges } })
end
game_edges()
hl.on("window.open", function() game_edges() end)
hl.on("window.close", function(win) game_edges(win and win.address) end)
-- (on every rule change, a focus or title too: only the tag looked at, no count unless a game makes it matter)
hl.on("window.update_rules", function(win) if edges and win and is_game(win) then game_edges() end end)
-- Games don't take focus back by themselves: Overwatch asks for attention the moment it loses focus, and Hyprland
-- (0.57+) then switched straight back to it, undoing Alt+Tab
hl.window_rule({ match = { tag = "game" }, focus_on_activate = false })
-- No animation for games: one moving or popping in (minimised with Alt+Tab, brought back) left Hyprland's black
-- fullscreen backdrop showing along the right and bottom edges for a moment
hl.window_rule({ match = { tag = "game" }, no_anim = true })
-- ...but a game takes the focus when it opens and when it goes fullscreen: focus goes on a click here, so Steam's window
-- (it shows when Lutris starts a game while Steam runs) kept it behind the game, and a Wine game gets mouse movement only
-- while focused: the camera didn't turn
local function focus_game(win)
    if win and (is_game(win) or steam_game_id(win.pid)) then hl.dispatch(hl.dsp.focus({ window = win })) end
end
hl.on("window.open", focus_game)
-- Only on the workspace you're on: the floating/tiling switch re-sends a game's fullscreen state, which took you to it
hl.on("window.fullscreen", function(win)
    local ws = hl.get_active_workspace()
    if win and win.fullscreen ~= 0 and ws and win.workspace and win.workspace.id == ws.id then focus_game(win) end
end)
-- Lower input lag in games (Settings app: games.low_latency): a game's frames go to the screen as soon as they're drawn
-- (Caelestia's "immediate" for the game tag, which needs tearing allowed; with the game's V-Sync off). Not direct
-- scanout: the pointer is drawn into the picture (hypr-user.lua), which a game's frames sent straight to the screen left
-- out
if dots.setting("games.low_latency") ~= false then hl.config({ general = { allow_tearing = true } }) end
-- Game audio only while the game is focused, a notification when a game wants attention (like Windows' orange
-- flash), fullscreen games on a free workspace (~/.local/bin/game-focus)
hl.on("hyprland.start", function() hl.exec_cmd("systemctl --user start game-focus") end)  -- a service: restarted if it crashes
-- Store launchers a game needs running (EA App, Ubisoft Connect, Epic, under Wine from Lutris) start minimised: only
-- when a game started them, and only windows their program opens in its first 2 minutes, so bringing one back from its
-- tray icon later still shows it. Opened yourself (from Lutris or a shortcut) they show. Can be turned off in the
-- Settings app
local launcher_classes = { ["eadesktop.exe"] = true, ["upc.exe"] = true, ["ubisoftconnect.exe"] = true,
                           ["epicgameslauncher.exe"] = true }
local launcher_titles = { ["EA"] = true, ["Ubisoft Connect"] = true, ["Epic Games Launcher"] = true }
local function process_age(pid)
    local stat, uptime = io.open("/proc/" .. pid .. "/stat"), io.open("/proc/uptime")
    local text, up = stat and stat:read("a"), uptime and uptime:read("a")
    if stat then stat:close() end
    if uptime then uptime:close() end
    -- Field 22, the start in clock ticks (100 a second) since boot; the name before it may hold spaces and ") ", so
    -- after the last ")". nil if the process went away meanwhile
    local fields = {}
    for field in ((text or ""):match("^.*%) (.*)") or ""):gmatch("%S+") do fields[#fields + 1] = field end
    local now, start = tonumber((up or ""):match("^%S+")), tonumber(fields[20])
    return now and start and now - start / 100
end
-- Started for a game: by what the game passed on to it. Lutris runs a game with GAME_NAME (its name: the launcher's own
-- entry, opened yourself, has the launcher's name), Steam with SteamGameId; a launcher opened some other way has neither
-- (whole names, as Lutris names their entries: "Assassin's Creed Origins" is a game, not Origin)
local launcher_names = { ["ea app"] = true, ["origin"] = true, ["ubisoft connect"] = true, ["uplay"] = true,
                         ["epic games store"] = true, ["epic games launcher"] = true, ["battle.net"] = true,
                         ["gog galaxy"] = true, ["rockstar games launcher"] = true }
function dots.started_for_game(pid)
    local env = pid and proc(pid, "environ")
    if not env then return false end
    env = "\0" .. env
    local steam = env:match("%zSteamGameId=(%d+)")
    if steam and steam ~= "0" then return true end
    local name = (env:match("%zGAME_NAME=([^%z]*)") or ""):lower()
    if name == "" then return false end
    return not launcher_names[name]
end
hl.on("window.open", function(win)
    if dots.setting("games.launchers_minimised") == false then return end
    if not (win and (launcher_classes[(win.initial_class or ""):lower()] or launcher_titles[win.initial_title or ""])) then return end
    if not dots.started_for_game(win.pid) then return end
    local age = win.pid and process_age(win.pid)
    if not age or age > 120 then return end
    -- Once it's on a workspace (not yet, the moment it opens). A sleep in its own process, not hl.timer: a config reload
    -- (likely at login, as the screens come up) would drop the timer
    hl.exec_cmd("sh -c 'sleep 0.3; exec hyprctl eval \"dots.minimise_launcher([[" .. win.address .. "]])\"'")
end)

function dots.minimise_launcher(address)
    -- Gone by then (a splash that closes at once): nothing, not the focused window minimise_window would take
    local w = hl.get_window("address:" .. address)
    if w then dots.minimise_window(w) end
end

-- Lutris lists every owned store game, the uninstalled ones below the installed (~/.local/bin/lutris-library)
hl.on("hyprland.start", function() hl.exec_cmd("systemctl --user start lutris-library.path") end)

-- Spotify: starts minimised to its tray icon (~/.local/bin/spotify-tray). Its window shows for a moment while
-- it starts, so spotify-tray turns these rules on meanwhile: the window opens out of sight (a hidden workspace
-- no key opens) until it's minimised; off otherwise, so opening Spotify shows it. tray-keeper turns them on too
-- when Caelestia restarts, as Spotify then shows its window. Not focusing it: Spotify asks to be focused,
-- which would bring that hidden workspace up
-- Whether they're on is kept in a file: a config reload meanwhile (the screens coming up at login, a Settings change)
-- makes the rules anew, and Spotify's window would show after all. Gone at each session's start (a stale one)
local silent_mark = os.getenv("HOME") .. "/.local/state/spotify-silent"
local function silent_marked()
    local f = io.open(silent_mark)
    if f then f:close() end
    return f ~= nil
end
-- (the rules too: they were made from the mark before this, at the config's first load)
hl.on("hyprland.start", function() dots.spotify_silent_set(false) end)
local silent = { workspace = "special:hidden silent", suppress_event = "activate activatefocus", no_initial_focus = true,
                 enabled = silent_marked() }
local function spotify_rule(match)
    local rule = { match = match }
    for k, v in pairs(silent) do rule[k] = v end
    return hl.window_rule(rule)
end
-- Each twice: also for a window with Caelestia's music_player tag (Spotify has it). A rule matching a tag beats one that
-- doesn't, whatever the order, so that tag's workspace "unset" (top of this file) kept Spotify's window in sight
local spotify_silent = {}
for _, match in ipairs({ { class = "^[Ss]potify$" }, { initial_title = "^Spotify( Free| Premium)?$" } }) do
    local tagged = { tag = "music_player" }
    for k, v in pairs(match) do tagged[k] = v end
    spotify_silent[#spotify_silent + 1] = spotify_rule(match)
    spotify_silent[#spotify_silent + 1] = spotify_rule(tagged)
end
function dots.spotify_silent_set(on)
    for _, r in ipairs(spotify_silent) do r:set_enabled(on) end
    if on then
        local f = io.open(silent_mark, "w")
        if f then f:close() end
    else
        os.remove(silent_mark)
    end
end
-- tray-keeper's fallback when Spotify's window popped up before the rules were on (a Caelestia crash)
function dots.spotify_hide(address)
    local w = hl.get_window("address:0x" .. address)
    if w then hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:hidden", follow = false })) end
end
-- spotify-tray's way back when minimising it to its tray didn't work: its windows from that hidden workspace (which no
-- key opens) onto the one you're on
function dots.spotify_show()
    local ws = hl.get_active_workspace()
    for _, w in ipairs(hl.get_windows() or {}) do
        if ws and (w.class or ""):lower() == "spotify" and w.workspace and w.workspace.name == "special:hidden" then
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = ws.id, follow = false }))
        end
    end
end

-- ArtCraft Launcher in its tray, also when it restarts after updating itself (~/.local/bin/artcraft-silent)
at_login("artcraft", "~/.local/bin/artcraft-silent")

-- Solaar in its tray (the mouse's battery), which puts the mouse's settings back when it reconnects, and the mouse DPI
-- chosen in the Settings app set now (~/.local/bin/mouse-dpi)
at_login("solaar", "~/.local/bin/app-launch solaar --window=hide")
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/mouse-dpi") end)

-- ...and keep it there when Caelestia (the tray) restarts or crashes; Spotify shows its window when the tray goes away.
-- tray-keeper also brings back tray icons apps like Proton VPN don't re-add themselves
hl.on("hyprland.start", function() hl.exec_cmd("systemctl --user start tray-keeper") end)  -- a service: restarted if it crashes

-- Capri (~/.local/bin/capri, class "Capri Desktop") sets her own window rules, by her windows' titles, and places herself.
-- Her key and her start at login only once she's installed (else her key would take Shift+Space from other apps): her
-- build (capri-update's), or the start script $CAPRI_RUN names (a checkout of her code: ~/.local/bin/capri runs it)
local function file_exists(path)
    local f = io.open(path)
    if f then f:close() end
    return f ~= nil
end
local home = os.getenv("HOME")
local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local capri_run = os.getenv("CAPRI_RUN")
if (capri_run and capri_run ~= "" and file_exists(capri_run)) or file_exists(data .. "/capri/current/package.json") then
    -- Put away / back (Shift+Space by default): apps can't have a shortcut of their own on Wayland, so it's bound here
    -- and passed to her local bridge. Switched off while a game has the focus (borderless too:
    -- dots.is_game) or a window is fullscreen where you are: bound, Hyprland takes the key from the game or app even
    -- when it does nothing (sprint + jump lost the jump, Shift seemed not to register). The tray still calls her out
    -- then. Any other app focused still loses Shift+Space to her: change her key in the Settings app if one needs it
    local capri_keys = dots.bind("capri", hl.dsp.exec_cmd("curl -s --max-time 2 -X POST http://127.0.0.1:47823/toggle"))
    local function capri_keys_follow()
        local ws = hl.get_active_workspace()
        local on = not (ws and ws.has_fullscreen) and not dots.is_game(hl.get_active_window())
        for _, b in ipairs(capri_keys) do b:set_enabled(on) end
    end
    -- Looked at just after each event: while it runs, a closing window is still there and a minimised one still on
    -- your workspace (a fullscreen game's kept them off). And as focus moves to another screen: an empty one beside a
    -- game's has no window to make it "active"
    local function capri_keys_soon() hl.timer(capri_keys_follow, { timeout = 1, type = "oneshot" }) end
    for _, ev in ipairs({ "window.fullscreen", "workspace.active", "window.active", "window.move_to_workspace",
                          "monitor.focused", "window.close" }) do
        hl.on(ev, capri_keys_soon)
    end
    capri_keys_follow()
    -- At login: silently (no intro)
    at_login("capri", "~/.local/bin/capri --hidden")  -- put away, only her tray icon: it or Shift+Space brings her out
end
