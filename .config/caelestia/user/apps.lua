-- Apps: where they open, how they start at login, and their window rules

-- No special workspaces: apps Caelestia sends to its music, communication, todo and system monitor ones
-- (Spotify, Equibop, btop...) open on the normal workspaces (their keys are off in hypr-vars.lua)
for _, tag in ipairs({ "music_player", "communication_app", "todo_app", "system_monitor" }) do
    hl.window_rule({ match = { tag = tag }, workspace = "unset" })
end

-- Apps started at login: only the ones you add (Settings app, Startup page: your autostart entries, each in a unit of
-- its own). None preset. Lutris, Proton VPN, Solaar and ArtCraft added there start quietly, in their tray
-- (dots-settings' LOGIN_EXEC)
-- Steam's own notification toasts ("friend started playing...") are windows: tag them like its menus, so the dock
-- doesn't show them
hl.window_rule({ match = { class = "steam", title = "notificationtoasts_.*" }, tag = "+xwl_popup" })
-- The live ISO's installer splash (named after its launcher entry: QS_APP_ID, agros-iso's calamares-online.sh): the
-- float and opaque Caelestia gives Quickshell windows (org.quickshell, its rules.lua). Set as such, not as its "float"
-- and "opaque" tags: a tag only takes effect from rules made before Caelestia's rule for it, which come before this file
hl.window_rule({ match = { class = "^agros-install$" }, float = true, opaque = true, tag = "+dots_opaque" })
-- LibreWolf opaque too (Caelestia's opacity for every other window left web pages see-through)
-- (both tagged dots_opaque too: window peek, user/windows.lua, fades them back to whole, as they are)
hl.window_rule({ match = { class = "^(librewolf)$" }, opaque = true, tag = "+dots_opaque" })
-- ...and the apps AgrOS opens your files in (mimeapps.list and the apps' own): Text Editor, gThumb, mpv, File Roller,
-- LibreOffice (a class per part: libreoffice-writer...) and VSCodium (codium; VSCodium under X11): through text, a
-- picture or a video, the windows behind showed. Not the terminal: see-through by design (its own colours)
hl.window_rule({ match = { class = "^(org\\.gnome\\.TextEditor|org\\.gnome\\.gthumb|mpv|org\\.gnome\\.FileRoller|"
                           .. "libreoffice-.+|soffice|codium|VSCodium)$" }, opaque = true, tag = "+dots_opaque" })
-- The installer (the live USB's): sized to the screen, in the middle; at its own size its summary page ran past the
-- bottom of a small screen and hid the Install button. Its main window only, by the product name in the title it opens
-- with ("AgrOS Installer", "Instalador AgrOS", "Instalador de AgrOS": its "%1 Installer" in the language it starts in):
-- its dialogs (an error's details) have its class too, and were stretched behind it. (Hyprland matches the whole title)
hl.window_rule({ match = { class = "^(io\\.calamares\\.calamares)$", initial_title = "^.*AgrOS.*$" }, float = true,
                 size = "(monitor_w*0.8) (monitor_h*0.9)", center = true })
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
-- A store launcher's window (EA app, Ubisoft Connect...): under Proton it gets the games' class, and so their tag. By
-- its program, as game-focus finds one: the list is ~/.local/bin/store-launchers (AgrOS's, updated with it; this file
-- is your account's copy), read once per config load; a line found as "\<line>" in its command line, lowercase, with
-- "/" and the breaks between arguments read as "\"
local launchers
local function store_launcher(pid)
    if not launchers then
        launchers = {}
        local p = io.popen((os.getenv("HOME") or "") .. "/.local/bin/store-launchers 2>/dev/null")
        for l in p and p:lines() or function() end do
            if l ~= "" then launchers[#launchers + 1] = "\\" .. l end
        end
        if p then p:close() end
    end
    local cmd = "\\" .. (proc(pid, "cmdline") or ""):lower():gsub("[/%z]", "\\")
    for _, l in ipairs(launchers) do
        if cmd:find(l, 1, true) then return true end
    end
    return false
end
-- dots.is_game: any game (Proton, Lutris/umu, gamescope, native Steam), also a native one before the tag below is on
-- (windows.lua and titlebars.lua's own window.open handlers can run first); not a store launcher's window. The same
-- as game-focus's is_game (after-games, --game-open)
function dots.is_game(win)
    return win ~= nil and (is_game(win) or steam_game_id(win.pid) ~= nil) and not store_launcher(win.pid)
end
hl.on("window.open", function(win)
    if win and not is_game(win) and steam_game_id(win.pid) then
        hl.dispatch(hl.dsp.window.tag({ tag = "+game", window = win }))
    end
end)
-- A store launcher's windows tagged store_launcher: under Proton they get the games' class and with it Caelestia's game
-- tag, which took their title bar (titlebars.lua gives it back by this tag: a launcher is a window like any other). The
-- windows already open at a config load too
local function tag_launcher(win)
    local tags = type(win.tags) == "table" and table.concat(win.tags, " ") or (win.tags or "")
    if win.pid and win.pid > 0 and not (" " .. tags .. " "):find(" store_launcher ", 1, true) and store_launcher(win.pid) then
        hl.dispatch(hl.dsp.window.tag({ tag = "+store_launcher", window = "address:" .. win.address }))
    end
end
hl.on("window.open", function(win) if win then tag_launcher(win) end end)
for _, w in ipairs(hl.get_windows() or {}) do tag_launcher(w) end
-- A store launcher's untitled windows are parts of its own, not windows: Epic draws its minimise, maximise and close
-- buttons as a window of their own (73x36, at its top right). Tagged like X11 menus (Caelestia's xwl_popup), so the
-- workspace icons, the dock and the switcher don't show them (as Caelestia does with Steam's untitled windows). A rule,
-- not a tag set once: one that gets a title later is a window again
hl.window_rule({ match = { tag = "store_launcher", title = "^$", xwayland = true }, tag = "+xwl_popup" })
-- Edge resizing (windows.lua) off while a game is open: Hyprland grows every floating window on a shown workspace by
-- 16 px for it, and a game, borderless over the whole screen but not fullscreen, then took a click on the next screen
-- beside it, or in a screen corner (its rounded corner: an RTS's camera scroll), as the start of a resize. On again
-- once the last one closes. Counted at every load (it sets this back on), as windows open and close (the closing one
-- still mapped then), and as one is tagged a game later (the tag above, a class rule matching after a class change)
local edges = true
-- (not on NVIDIA: its driver loses the screen's flips while a game tears, and the game froze on one frame until
-- something was drawn over it, Overwatch under Wine's Wayland driver for HDR. SYSFS: another /sys, the tests')
local nvidia = io.open((os.getenv("SYSFS") or "/sys") .. "/module/nvidia_drm/initstate")
if nvidia then nvidia:close() end
local low_latency = dots.setting("games.low_latency") ~= false and not nvidia
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
-- With lower input lag on (below), the pointer drawn into the picture while a game has the focus: Hyprland allows no
-- tearing while the graphics card's cursor layer shows a pointer (a game's menus, a strategy game's camera), so the
-- lag came back there. The cursor layer whenever anything else has it: drawn into the picture, the pointer on another
-- screen (taken out of the game, crossing.lua) went at that screen's refresh rate and left ghosts behind it
local soft
local function game_cursor()
    local w = hl.get_active_window()
    local want = low_latency and w ~= nil and is_game(w)
    if want == soft then return end
    soft = want
    hl.config({ cursor = { no_hardware_cursors = soft and 1 or 2 } })
end
game_cursor()
hl.on("window.active", function() game_cursor() end)
hl.on("window.close", function() game_cursor() end)
hl.on("monitor.focused", function() game_cursor() end)  -- (onto a screen with no window: none active)
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
    if dots.is_game(win) then hl.dispatch(hl.dsp.focus({ window = win })) end
end
hl.on("window.open", focus_game)
-- Only on the workspace you're on: the floating/tiling switch re-sends a game's fullscreen state, which took you to it.
-- And only the first time a window goes fullscreen: a game in exclusive fullscreen leaves it and comes straight back
-- each time it loses focus, and focusing it then pulled the focus back from the other screen the pointer had gone to,
-- several times a second (Overwatch under Wine's Wayland driver stopped on one frame, minimised in the dock)
local went_fullscreen = {}
hl.on("window.fullscreen", function(win)
    local ws = hl.get_active_workspace()
    if not (win and win.fullscreen ~= 0 and ws and win.workspace and win.workspace.id == ws.id) then return end
    if went_fullscreen[win.address] then return end
    went_fullscreen[win.address] = true
    focus_game(win)
end)
hl.on("window.close", function(win) if win then went_fullscreen[win.address] = nil end end)
-- A game in exclusive fullscreen: it leaves fullscreen the moment it loses the focus, and stops drawing until it has it
-- back (on Windows too). Windows keeps the pointer on such a game's screen; crossing.lua does the same for it (Alt+Tab
-- and Super still leave it), not taking the focus to the other screen as for any other game. Known by that: leaving
-- fullscreen while another window has the focus, on its own workspace (not minimised to a hidden one)
-- Only such a game gets what follows from it (a borderless one, never leaving fullscreen, none of it): tagged
-- exclusive_fs, which the shell hides over while it covers its screen (drawers/PartWindow.qml) and which takes off its
-- rounded corners, border and shadow, as it drops fullscreen for a moment each time it gets the focus back (windows.lua
-- puts it back, and also marks it so on that drop)
dots.exclusive_fullscreen = {}
function dots.mark_exclusive(win)
    if dots.exclusive_fullscreen[win.address] then return end
    dots.exclusive_fullscreen[win.address] = true
    hl.dispatch(hl.dsp.window.tag({ tag = "+exclusive_fs", window = "address:" .. win.address }))
end
hl.window_rule({ match = { tag = "exclusive_fs" }, rounding = 0, border_size = 0, no_shadow = true })
-- ...and unmarked once it shows it isn't any more: switched to borderless in its own settings, it stays fullscreen
-- without the focus (an exclusive one drops it within milliseconds); looked at 300 ms after another window got it
local function unmark_exclusive(address)
    dots.exclusive_fullscreen[address] = nil
    hl.dispatch(hl.dsp.window.tag({ tag = "-exclusive_fs", window = "address:" .. address }))
end
hl.on("window.active", function(win)
    for address in pairs(dots.exclusive_fullscreen) do
        if not (win and win.address == address) and hl.timer then
            hl.timer(function()
                local g, now = hl.get_window("address:" .. address), hl.get_active_window()
                if g and dots.exclusive_fullscreen[address] and (g.fullscreen or 0) >= 2 and not (now and now.address == address) then
                    unmark_exclusive(address)
                end
            end, { timeout = 300, type = "oneshot" })
        end
    end
end)
hl.on("window.fullscreen", function(win)
    if not (win and (win.fullscreen or 0) < 2 and win.workspace and (win.workspace.id or 0) > 0 and dots.is_game(win)) then
        return
    end
    -- (focus on another workspace, the other screen's: Hyprland takes a game out of fullscreen itself for a window on
    -- its own workspace, which a borderless one is too)
    local active = hl.get_active_window()
    if not active or active.address ~= win.address and not (active.workspace and active.workspace.id == win.workspace.id) then
        dots.mark_exclusive(win)
    end
end)
-- (marks from before a config load cleared: the list above starts empty again)
if not dots.verifying then
    for _, w in ipairs(hl.get_windows() or {}) do
        for _, t in ipairs(w.tags or {}) do
            if t:gsub("%*$", "") == "exclusive_fs" then
                hl.dispatch(hl.dsp.window.tag({ tag = "-exclusive_fs", window = "address:" .. w.address }))
            end
        end
    end
end
hl.on("window.close", function(win) if win then dots.exclusive_fullscreen[win.address] = nil end end)
-- A game's splash screen (its first window, small: Batman: Arkham Knight's logo) shown alone: the game's other windows
-- opening meanwhile (its main window, still white while it loads) kept out of sight, on a hidden workspace, until the
-- splash closes, then shown where it was. At most 30 s (a small first window that isn't a splash never hides the game
-- for long). By the game's process: its windows, and the splash's own workspace to come back to
local splash = {}  -- pid -> { address = splash's, workspace = its id, held = { addresses } }
-- (the window's size is in the screen's units: its mode over its scale)
local function small(win)
    local m = win.monitor or hl.get_active_monitor()
    return m and win.size and win.fullscreen == 0 and win.size.x * win.size.y < 0.5 * m.width * m.height / (m.scale or 1) ^ 2
end
function dots.splash_release(pid)
    local s = splash[tonumber(pid)]
    if not s then return end
    splash[tonumber(pid)] = nil
    for _, address in ipairs(s.held) do
        local w = hl.get_window("address:" .. address)
        if w then
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = s.workspace, follow = false }))
            hl.dispatch(hl.dsp.focus({ window = w }))
        end
    end
end
hl.on("window.open", function(win)
    if not (win and win.pid and win.pid > 0 and dots.is_game(win)) then return end
    local s = splash[win.pid]
    if s and hl.get_window("address:" .. s.address) then
        s.held[#s.held + 1] = win.address
        hl.dispatch(hl.dsp.window.move({ window = win, workspace = "special:splash", follow = false }))
        return
    end
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.pid == win.pid and w.address ~= win.address then return end  -- (not its first window)
    end
    if small(win) and win.workspace and (win.workspace.id or 0) > 0 then
        splash[win.pid] = { address = win.address, workspace = win.workspace.id, held = {} }
        -- (a sleep in its own process, not hl.timer: a config reload would drop the timer)
        hl.exec_cmd("sh -c 'sleep 30; exec hyprctl eval \"dots.splash_release(" .. win.pid .. ")\"'")
    end
end)
hl.on("window.close", function(win)
    for pid, s in pairs(splash) do
        if win and s.address == win.address then dots.splash_release(pid) end
    end
end)
-- Lower input lag in games (Settings app: games.low_latency): a game's frames go to the screen as soon as they're drawn
-- (Caelestia's "immediate" for the game tag, which needs tearing allowed; with the game's V-Sync off), the pointer drawn
-- into the picture meanwhile (game_edges, above)
if low_latency then hl.config({ general = { allow_tearing = true } }) end
-- Game audio only while the game is focused, a notification when a game wants attention (like Windows' orange
-- flash), fullscreen games on a free workspace (~/.local/bin/game-focus)
hl.on("hyprland.start", function() hl.exec_cmd("systemctl --user start game-focus") end)  -- a service: restarted if it crashes
-- Store launchers a game needs running (EA App, Ubisoft Connect, Epic... under Wine from Lutris) start minimised: only
-- when a game started them, and only windows their program opens in its first 2 minutes, so bringing one back from its
-- tray icon later still shows it. Opened yourself (from Lutris or a shortcut) they show. Can be turned off in the
-- Settings app
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
    -- Steam's own client, which Lutris starts with the first game's GAME_NAME: not that game's window (opened over the
    -- game, it didn't minimise it, and the game stayed over the screen, black)
    local comm = (proc(pid, "comm") or ""):gsub("%s+$", "")
    if comm == "steam" or comm == "steamwebhelper" then return false end
    local name = (env:match("%zGAME_NAME=([^%z]*)") or ""):lower()
    if name == "" then return false end
    return not launcher_names[name]
end

-- A Wine game's own program, noted as its window opens: its Lutris name (GAME_NAME, as Lutris starts it) and its .exe
-- on disk, in ~/.local/state/agros/wine-games.tsv. lutris-library takes the game's menu icon from it and tells the dock
-- its windows by it: a game a store's launcher starts (Epic's, EA's, Ubisoft's...) had the launcher's icon and was
-- told apart as the launcher. Not the launchers' own windows (started for themselves, or not games); once per game
-- and program (the file written only when one is new or changed)
local wine_games_file = (os.getenv("HOME") or "") .. "/.local/state/agros/wine-games.tsv"
hl.on("window.open", function(win)
    if not (win and win.pid and win.pid > 0 and dots.is_game(win)) then return end
    local env = proc(win.pid, "environ")
    if not env then return end
    env = "\0" .. env
    local name, prefix = env:match("%zGAME_NAME=([^%z]+)"), env:match("%zWINEPREFIX=([^%z]+)")
    if not name or not prefix or launcher_names[name:lower()] then return end
    local exe = (proc(win.pid, "cmdline") or ""):match("^([^%z]+)") or ""
    local drive, rest = exe:match("^(%a):[\\/](.+%.[eE][xX][eE])$")
    if not drive then return end
    local path = prefix:gsub("/+$", "") .. "/dosdevices/" .. drive:lower() .. ":/" .. rest:gsub("\\", "/")
    local lines, found, changed = {}, false, true
    local f = io.open(wine_games_file, "r")
    for line in f and f:lines() or function() end do
        local n, p = line:match("^([^\t]+)\t(.*)$")
        if n == name then
            found, changed = true, p ~= path
            lines[#lines + 1] = name .. "\t" .. path
        else
            lines[#lines + 1] = line
        end
    end
    if f then f:close() end
    if found and not changed then return end
    if not found then lines[#lines + 1] = name .. "\t" .. path end
    os.execute("mkdir -p " .. (os.getenv("HOME") or "") .. "/.local/state/agros")
    f = io.open(wine_games_file, "w")
    if not f then return end
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    hl.exec_cmd("systemctl --user start lutris-library.service")
end)
hl.on("window.open", function(win)
    if dots.setting("games.launchers_minimised") == false then return end
    -- (any of ~/.local/bin/store-launchers' list: Battle.net, GOG Galaxy and Rockstar's too, which stayed shown)
    if not (win and store_launcher(win.pid)) then return end
    if not dots.started_for_game(win.pid) then return end
    local age = win.pid and process_age(win.pid)
    if not age or age > 120 then return end
    -- Once it's on a workspace (not yet, the moment it opens). A sleep in its own process, not hl.timer: a config reload
    -- (likely at login, as the screens come up) would drop the timer
    hl.exec_cmd("sh -c 'sleep 0.3; exec hyprctl eval \"dots.minimise_launcher([[" .. win.address .. "]])\"'")
end)

-- Epic's tray icon, its menu in the shell's (~/.local/bin/epic-tray: your installed Epic games, Library, Store, Unreal
-- Engine, Exit): started as Epic's window opens, and quits with Epic. Under a Proton that gives it no tray icon of its
-- own (CachyOS's) Epic had none; one that does (GE-Proton) showed its menu as Epic's own window. One at a time: a second
-- one quits. Epic's window already open at a config load too
local function epic_tray(win)
    if win and (win.initial_title == "Epic Games Launcher" or win.title == "Epic Games Launcher") then
        hl.exec_cmd("~/.local/bin/epic-tray")
    end
end
hl.on("window.open", epic_tray)
if not dots.verifying then
    for _, w in ipairs(hl.get_windows() or {}) do epic_tray(w) end
end

-- Wine's own tray window (its explorer.exe /desktop's, untitled): a Windows program's tray icon with no XEmbed tray to
-- dock in (Hyprland has none, nor Wine's Wayland driver) shows in a window of its own, white and full-screen over a
-- game under Wayland mode (Batman). Closed as it opens, whatever started Wine (Lutris, Steam's Proton, Heroic...):
-- closing only hides it, Wine and the game go on. Lutris's games have it off already (ShowSystray=0, lutris-overlay's
-- services_on_desktop and desktop_value_only); this is for when that's left out (a Lutris update it no longer fits)
-- or another launcher started Wine. Not a virtual desktop's window (/desktop=name,size): that one has a title
local function wine_tray(win)
    if not (win and win.pid and win.pid > 0) or (win.title or "") ~= "" then return false end
    local args = {}
    for a in (proc(win.pid, "cmdline") or ""):gmatch("[^%z]+") do args[#args + 1] = a end
    if not (args[1] or ""):lower():find("\\explorer%.exe$") then return false end
    for i = 2, #args do
        if args[i] == "/desktop" or args[i]:find("^/desktop=") then return true end
    end
    return false
end
-- (half a second on, once it's there, and still untitled: a window that gets its title late isn't the tray's)
function dots.close_wine_tray(address)
    local w = hl.get_window("address:" .. address)
    if wine_tray(w) then hl.dispatch(hl.dsp.window.close({ window = w })) end
end
hl.on("window.open", function(win)
    if wine_tray(win) then
        hl.exec_cmd("sh -c 'sleep 0.5; exec hyprctl eval \"dots.close_wine_tray([[" .. win.address .. "]])\"'")
    end
end)

function dots.minimise_launcher(address)
    -- Gone by then (a splash that closes at once): nothing, not the focused window minimise_window would take
    local w = hl.get_window("address:" .. address)
    if w then dots.minimise_window(w) end
end

-- An app you start at login minimised (Settings app, Startup: dots-settings writes its entry's command with
-- AGROS_START_MINIMISED=1): its windows of the first minute go to the dock as they open. Lutris, Proton VPN...
-- start in their tray by their own options instead
-- The first minute is the app's as the login started it: the age of the topmost process with the mark, not the
-- window's own. Whatever it starts inherits the mark: a game from Steam started so, a link Discord opened in a browser
-- not running yet, had their windows minimised as they opened
local function start_minimised(pid)
    local env = proc(pid, "environ")
    return env ~= nil and ("\0" .. env):find("%zAGROS_START_MINIMISED=1%z") ~= nil
end
local function started_minimised_age(pid)
    for _ = 1, 64 do
        -- (its parent: the field after its state, after the last ")", as process_age reads them)
        local parent = tonumber((proc(pid, "stat") or ""):match("^.*%) %S+ (%d+)"))
        if not (parent and parent > 1 and start_minimised(parent)) then break end
        pid = parent
    end
    return process_age(pid)
end
hl.on("window.open", function(win)
    if not (win and win.pid and win.pid > 0 and start_minimised(win.pid)) then return end
    local age = started_minimised_age(win.pid)
    if not age or age > 60 then return end
    -- (once it's on a workspace, as the launchers above)
    hl.exec_cmd("sh -c 'sleep 0.3; exec hyprctl eval \"dots.minimise_launcher([[" .. win.address .. "]])\"'")
end)

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

-- The mouse DPI chosen in the Settings app, set at login (~/.local/bin/mouse-dpi; Solaar, when you add it to Startup,
-- puts the mouse's settings back when it reconnects)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/mouse-dpi") end)

-- The night light (gammastep: warmer screens after sunset, ~/.config/gammastep/config.ini), when you turn it on (off
-- at first; Settings app, Screens page). Caelestia's execs.lua started it at every login: taken out there
-- (agros-hyprland-settings' _execs_sed)
if dots.setting("nightlight") then hl.on("hyprland.start", function() hl.exec_cmd("gammastep") end) end

-- ...and keep it there when Caelestia (the tray) restarts or crashes; Spotify shows its window when the tray goes away.
-- tray-keeper also brings back tray icons apps like Proton VPN don't re-add themselves
hl.on("hyprland.start", function() hl.exec_cmd("systemctl --user start tray-keeper") end)  -- a service: restarted if it crashes
