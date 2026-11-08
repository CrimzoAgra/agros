-- Keys: the Super+Tab / Alt+Tab switchers, Scroll Lock, lock badges, and binds of my own. (Window binds: windows.lua.)
-- dots.bind binds take their keys from the Settings app (Keyboard page); the keys named here are the defaults
-- Caelestia's own binds for the same keys (Alt+Tab window cycling, Print, Super+Alt+Space, Super+Alt+F) are turned off
-- in hypr-vars.lua, so nothing here has to undo them

-- Super+Tab: workspace switcher with previews (~/.config/quickshell/switcher); releasing Super goes there
-- Global shortcuts, not commands: they reach it in order, so a quick Super+Tab can't leave it open
dots.bind("switcher_next", hl.dsp.global("switcher:next"))
dots.bind("switcher_prev", hl.dsp.global("switcher:prev"))
-- Alt+Tab: the same switcher for the workspace's windows (last used first); releasing Alt goes there
dots.bind("windows_next", hl.dsp.global("switcher:windows-next"))
dots.bind("windows_prev", hl.dsp.global("switcher:windows-prev"))
-- Releasing Super or Alt picks. A key hook, not a release bind: Hyprland drops a release bind once another key (the
-- Tab) was pressed in between (which is also why Caelestia's Super-release launcher stays shut). Codes as this hook
-- gets them (evdev + 8): left Super 133, right Super 134, left Alt 64, right Alt 108
-- (In the one key hook at the end of this file, with the other two: it runs on every key press and release)
hl.layer_rule({ match = { namespace = "workspace-switcher" }, blur = true, ignore_alpha = 0.3, animation = "fade" })
hl.on("hyprland.start", function() hl.exec_cmd("qs -c switcher -d") end)

-- Scroll Lock as a real lock with its keyboard light, like Caps and Num Lock (~/.local/bin/scroll-lock makes
-- the keymap of the system layout with Scroll Lock working), and the bar's badge following the light
local keymap = io.popen("~/.local/bin/scroll-lock keymap")
local kb_file = keymap and keymap:read("l")
if keymap then keymap:close() end
if kb_file and kb_file ~= "" then hl.config({ input = { kb_file = kb_file } }) end
hl.on("hyprland.start", function() hl.exec_cmd("~/.local/bin/scroll-lock sync") end)
-- On the key's release: code 78 (evdev 70 + 8, as this hook gets codes; 70 here is F4).
-- Not a bind: those don't match it, as the key holds Mod3 itself now (the key hook below)

-- Caps/Num Lock badges in the bar: Hyprland keeps each keyboard's locks apart and reports the "main" one, which is
-- the last keyboard used (the Razer alone is three; keyboards come back as new ones after sleep). Caelestia only
-- re-reads them on the Caps/Num keys, so a change of main keyboard left a wrong badge. On a key release (at most once a
-- second: a game's key presses don't each scan every device): if the main keyboard or its locks changed, have
-- Caelestia re-read them
local last_locks, last_scan, check_due
local function check_locks()
    if os.time() == last_scan then
        -- Checked this second already: once more a second later, so the last key of a burst isn't left out
        if not check_due then
            check_due = true
            hl.timer(function()
                check_due, last_scan = false, nil
                check_locks()
            end, { timeout = 1000, type = "oneshot" })
        end
        return
    end
    last_scan = os.time()
    local locks
    for _, d in ipairs(hl.get_devices() or {}) do
        if d.type == "keyboard" and d.main then locks = d.name .. tostring(d.caps_lock) .. tostring(d.num_lock) end
    end
    if locks ~= last_locks then
        last_locks = locks
        hl.dispatch(hl.dsp.global("caelestia:refreshDevices"))
    end
end

-- The key hook: releases only (presses return at once)
hl.on("input.keyboard.key", function(key, _, pressed)
    if pressed ~= 0 then return end
    if key == 133 or key == 134 or key == 64 or key == 108 then  -- Super or Alt: the switcher picks
        hl.dispatch(hl.dsp.global("switcher:commit"))
    elseif key == 78 then  -- Scroll Lock
        hl.exec_cmd("~/.local/bin/scroll-lock sync")
    end
    check_locks()
end)

-- Ctrl+Shift+Esc: btop, like Task Manager (also in the bar's right-click menu): the one already open, or a new one
-- started as Caelestia's system monitor key starts it (a normal window here: no special workspaces, hypr-vars.lua)
function dots.task_manager()
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.class == "btop" then return dots.focus_window(w.address) end
    end
    hl.exec_cmd("~/.local/bin/app-launch foot -a btop -T btop fish -C 'exec btop'")
end
dots.bind("task_manager", function() dots.task_manager() end)

-- Print Screen: dim the screen and select an area (like Windows)
dots.bind("screenshot", hl.dsp.global("caelestia:screenshotFreeze"))

-- Restart Caelestia (Ctrl+Super+Alt+R) through caelestia-restart, which keeps Spotify's window hidden.
-- Caelestia's shell restart bind has no hypr-vars.lua variable, so it's replaced here
pcall(hl.unbind, "CTRL + SUPER + ALT + R")
dots.bind("restart_shell", hl.dsp.exec_cmd("~/.local/bin/caelestia-restart"), { release = true })

-- Recording a shortcut in the Settings app: this submap has no binds, so every key reaches the app (Super+Q too).
-- Esc always leaves it (and still reaches the app, which cancels); the app leaves it when done
hl.define_submap("dots-capture", function()
    hl.bind("Escape", hl.dsp.submap("reset"), { non_consuming = true })
end)

-- A VMware window focused: every key reaches the VM (a submap with no other binds), so its desktop's shortcuts (Super
-- ones too) work there; back to these once another window has focus, or Ctrl+Alt+Esc (none of the VM's) right away
hl.define_submap("vm", function()
    hl.bind("CTRL + ALT + Escape", hl.dsp.submap("reset"))
end)
local function vm_keys(win)
    local vm, current = win ~= nil and (win.class or ""):lower() == "vmware", hl.get_current_submap()
    if vm and current ~= "vm" and current ~= "dots-capture" then
        hl.dispatch(hl.dsp.submap("vm"))
    elseif not vm and current == "vm" then
        hl.dispatch(hl.dsp.submap("reset"))
    end
end
hl.on("window.active", vm_keys)
vm_keys(hl.get_active_window())  -- (VMware already focused when the config loads: no event comes)
