-- The desktop around Caelestia: widgets, login screen, and what runs once at login

-- Desktop widgets (~/.config/quickshell/widgets): blur behind their cards only, not the whole layer
hl.layer_rule({ match = { namespace = "desktop-widgets" }, blur = true, ignore_alpha = 0.2 })
-- Started once Caelestia has loaded (~/.local/bin/widgets-start)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/widgets-start") end)

-- Login screen: copy the current wallpaper and Caelestia colours to it
-- Code: ~/.local/share/caelestia-greeter (install with sudo bash install.sh)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/greeter-theme-sync") end)

-- Clear the text console under the desktop, so no old text shows when the desktop closes (shutdown)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/console-clear") end)

-- Passwords keyring: make "login" (unlocked by the login password) the default, before apps use it
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/keyring-default") end)

-- Bluetooth: always unblocked and powered on at login (bluetooth-on does nothing without an adapter)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/bluetooth-on") end)

-- In a VM: the screen follows its window and full screen (vm-screen-follow does nothing elsewhere)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/vm-screen-follow") end)

-- The time zone from your location, when Settings > Language & region says so (timezone-auto does nothing otherwise)
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/timezone-auto") end)

-- Updates: a notification with an "Update now" button when updates are waiting (~/.local/bin/update-apps; the boot
-- update covers the rest). 15 minutes after login, then every 6 hours
-- (the first check from here, not the timer: any daemon-reload restarts a timer's OnActiveSec count)
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start update-check.timer")
    hl.exec_cmd("sh -c 'sleep 900; exec systemctl --user start update-check.service'")
end)

-- After login settles: a notification if a Hyprland or Caelestia update broke something of these dotfiles
-- (config errors, Caelestia patches that no longer fit, services down or logging errors; ~/.local/bin/dotfiles-check)
-- (A sleep in its own process, not hl.timer: a config reload at login would drop the timer)
hl.on("hyprland.start", function() hl.exec_cmd("sh -c 'sleep 30; exec ~/.local/bin/dotfiles-check --notify'") end)
