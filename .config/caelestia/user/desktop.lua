-- The desktop around Caelestia: widgets, login screen, and what runs once at login

-- Desktop widgets (~/.config/quickshell/widgets): blur behind their cards only, not the whole layer
hl.layer_rule({ match = { namespace = "desktop-widgets" }, blur = true, ignore_alpha = 0.2 })
-- Started once Caelestia has loaded (~/.local/bin/widgets-start)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/widgets-start") end)

-- Login screen: copy the current wallpaper and Caelestia colours to it, and which screen is the main one (again at each
-- config reload: a main screen set in the Settings app, screens plugged in, reload it)
-- Code: ~/.local/share/caelestia-greeter (installed by the agros-greeter package)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/greeter-theme-sync") end)
hl.on("config.reloaded", function() hl.exec_cmd("~/.local/bin/greeter-theme-sync") end)

-- The main screen as XWayland's primary one, the screen Wine's full screen games are drawn for (with none, another
-- screen's size: the game on part of the screen, clicks elsewhere). Again at each config reload, as above
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/xwayland-primary") end)
hl.on("config.reloaded", function() hl.exec_cmd("~/.local/bin/xwayland-primary") end)
-- (and as a screen comes back: XWayland makes its outputs anew without a primary, and the reload for it waits while a
-- game runs, the very time Wine needs one: clicks off, the pointer offset)
hl.on("monitor.added", function() hl.exec_cmd("~/.local/bin/xwayland-primary") end)

-- Screens asleep and awake together. A DisplayPort screen asleep disconnects (the MSI, seconds after "dpms off"), and
-- Hyprland turns a screen that connects on whatever the others are: one that comes back while the rest sleep sleeps
-- with them (a key or the mouse wakes them all). And the lock screen's keyboard: the screen that had it gone, Hyprland
-- hands it to the one under the pointer only as the pointer moves (a key only wakes the screens), so typing went
-- nowhere till a click: the pointer moved to where it is. (Timers: the screen's rule applied first, the list settled)
if hl.timer and not dots.verifying then
    hl.on("monitor.added", function(mon)
        local name = mon and mon.name
        hl.timer(function()
            local others = 0
            for _, m in ipairs(hl.get_monitors()) do
                if m.name ~= name then
                    if m.dpms_status then return end
                    others = others + 1
                end
            end
            if name and others > 0 then hl.dispatch(hl.dsp.dpms({ action = "off", monitor = name })) end
        end, { timeout = 200, type = "oneshot" })
    end)
    hl.on("monitor.removed", function()
        hl.timer(function()
            local p = hl.get_cursor_pos()
            if p then hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end
        end, { timeout = 200, type = "oneshot" })
    end)
end

-- Clear the text console under the desktop, so no old text shows when the desktop closes (shutdown)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/console-clear") end)
-- The pointer on the graphics card's cursor layer (Hyprland's default: it follows the mouse with no lag; drawn into the
-- picture it trailed behind, floaty, most in a VM), hidden as the computer powers off, as nothing clears that layer
-- when the desktop closes and it stayed on the shutdown screen
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/cursor-hide-at-shutdown") end)

-- Passwords keyring: make "login" (unlocked by the login password) the default, before apps use it
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/keyring-default") end)

-- Bluetooth: always unblocked and powered on at login (bluetooth-on does nothing without an adapter)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/bluetooth-on") end)

-- In a VM: the screen follows its window and full screen (vm-screen-follow does nothing elsewhere)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/vm-screen-follow") end)

-- The time zone from your location, when Caelestia's own Settings app (not Desktop Settings), Language & region page,
-- says so (timezone-auto does nothing otherwise)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/timezone-auto") end)

-- Updates: a notification with an "Update now" button when updates are waiting (~/.local/bin/update-apps; the boot
-- update covers the rest). 15 minutes after login, then every 6 hours
-- (the first check from here, not the timer: any daemon-reload restarts a timer's OnActiveSec count)
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start update-check.timer")
    hl.exec_cmd("sh -c 'sleep 900; exec systemctl --user start update-check.service'")
end)

-- After login settles: a notification if a Hyprland or Caelestia update broke something of these dotfiles
-- (config errors, Caelestia patches that no longer fit, services down or logging errors; ~/.local/bin/agros-check)
-- (A sleep in its own process, not hl.timer: a config reload at login would drop the timer)
hl.on("hyprland.start", function() hl.exec_cmd("sh -c 'sleep 30; exec ~/.local/bin/agros-check --notify'") end)
