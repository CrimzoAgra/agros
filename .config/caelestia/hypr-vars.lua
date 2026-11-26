-- Caelestia's variables I change (~/.config/hypr/variables.lua has them all)
local vars = {
    -- The pointer: Bibata (Caelestia's sweet-cursors isn't installed)
    cursorTheme = "Bibata-Modern-Ice",
    browser = "librewolf",  -- Super+W: Caelestia's is Firefox, which AgrOS leaves out (LibreWolf instead)
    -- Sleep (Super+Shift+L, the touchpad's 4-finger swipe down): plain suspend where hibernating can't work, as on
    -- CachyOS's default zram-only swap (Caelestia's suspend-then-hibernate alone then did nothing)
    sleepGestureCmd = "systemctl suspend-then-hibernate || systemctl suspend",

    -- No special workspaces (the music, communication, todo, system monitor and general ones): their keys
    -- aren't bound, and user/apps.lua cancels the rules sending apps there, so everything uses the normal ones (the
    -- touchpad's swipes to the general one: user/workspaces.lua)
    kbSpecialWs            = "",
    kbSystemMonitorWs      = "",  -- Ctrl+Shift+Esc opens btop as a normal window instead (user/keys.lua)
    kbMusicWs              = "",
    kbCommunicationWs      = "",
    kbTodoWs               = "",
    kbMoveWinToWsSpecial   = "",
    kbMoveWinFromWsSpecial = "",

    -- Keys bound to something else: in user/keys.lua Alt+Tab opens the window switcher (Super+Tab the workspace
    -- one) and Print selects an area (not a full-screen shot); in user/windows.lua Super+Alt+Space switches every
    -- window between floating and tiling and Super+Alt+F maximises a floating window inside the gaps
    kbWindowCycleNext          = "",
    kbWindowCyclePrev          = "",
    kbScreenshot               = "",
    kbToggleWindowFloating     = "",
    kbWindowBorderedFullscreen = "",
    -- Clear every notification: Ctrl+Alt+C, as Caelestia has it
    kbClearNotifs              = "CTRL + ALT + C",
}

-- Its shortcuts changed in the Settings app (Shortcuts page): caelestia-keys.<variable>, a list of shortcuts, in
-- ~/.config/dots/settings.lua (~/.local/bin/dots-settings). One as a plain string: the "mod + 0-9" ones must be.
-- The ones turned off above aren't listed there, so these can't undo them. A value that isn't a list (a hand edit of
-- settings.json) is left alone: an error here, in the first file Caelestia loads and unguarded, would take the whole
-- config down. Its other variables changed there (Look and Mouse and keyboard pages: gaps, borders, the touchpad):
-- caelestia-vars.<variable>, a number, true/false or text, over the ones above
local ok, settings = pcall(dofile, os.getenv("HOME") .. "/.config/dots/settings.lua")
for key, keys in pairs(ok and type(settings) == "table" and settings or {}) do
    -- (a key that isn't a string, from a hand edit of settings.lua, is skipped too: indexing it errored)
    local var = type(key) == "string" and key:match("^caelestia%-keys%.(kb%w+)$")
    if var and type(keys) == "table" then vars[var] = #keys == 1 and keys[1] or (#keys == 0 and "" or keys) end
    local other = type(key) == "string" and key:match("^caelestia%-vars%.(%w+)$")
    if other and type(keys) ~= "table" then vars[other] = keys end
end
-- In a VMware virtual machine (its virtual GPU, the vmwgfx driver): Hyprland draws on that GPU (window animations,
-- blur), the apps on the CPU. Apps' GPU-drawn buffers from it are refused ("invalid arguments for wl_surface.attach")
-- and the app dropped: Quickshell (the shell, widgets), Qt apps and XWayland (so every X11 app: Nuvio...). Never in
-- Hyprland's own environment: set before it starts, it took Hyprland's own renderer down to the CPU too
-- (agros-system's agros-vm.sh used to set it for the whole session, in every VM: Hyprland too, on the CPU)
-- Not when Hyprland runs with agros-vmware's vmw-dmabuf shim (its drop-in for Hyprland's uwsm unit): it makes Hyprland accept those
-- buffers, so the apps stay on the GPU too. The shim is Hyprland's only: taken out for every app it starts (any other
-- preload of the session's kept)
-- (entry by entry: a pattern left a trailing ':' when the shim wasn't first)
local preload, kept = os.getenv("LD_PRELOAD") or "", {}
for entry in preload:gmatch("[^:]+") do
    if entry ~= "/usr/lib/agros/vmw-dmabuf.so" then kept[#kept + 1] = entry end
end
if table.concat(kept, ":") ~= preload then hl.env("LD_PRELOAD", table.concat(kept, ":")) end
-- VMware by its vmwgfx driver being loaded, as the login screen and the shim's drop-in tell it, not by card0's vendor:
-- with simpledrm in the kernel the real GPU is often card1. (Opening the folder only proves it's there)
local f = io.open((os.getenv("SYSFS") or "/sys") .. "/module/vmwgfx")
local vmware = f ~= nil
if f then f:close() end
-- (Hyprland's maps read in VMware alone: this file runs again at every reload, on every machine)
local maps = vmware and io.open("/proc/self/maps")
local shim = maps and maps:read("a"):find("vmw-dmabuf", 1, true)
if maps then maps:close() end
local cpu_apps = vmware and not shim
-- Most apps aren't Hyprland's children: under uwsm, XDG autostart, `uwsm app` (app-launch) and D-Bus activation start
-- them as systemd user units, with the user manager's environment. So into it (and D-Bus's) too, here as the config
-- loads: before Hyprland puts WAYLAND_DISPLAY there, which uwsm waits for before graphical-session.target (autostart
-- after it), so nothing starts without them. uwsm takes them out again at logout: its start of Hyprland (aux exec)
-- lists every variable that reaches the user manager before WAYLAND_DISPLAY does, and its cleanup-env unsets that list
-- (not for a check of the config: its process has no shim to find; nor on a reload: Hyprland has them by then)
if cpu_apps and os.getenv("DOTS_VERIFY_CONFIG") ~= "1" and os.getenv("LIBGL_ALWAYS_SOFTWARE") ~= "1" then
    local set = "LIBGL_ALWAYS_SOFTWARE=1 XWAYLAND_NO_GLAMOR=1"
    os.execute("systemctl --user set-environment " .. set .. "; dbus-update-activation-environment " .. set .. " 2>/dev/null")
end
-- And for what Hyprland starts itself, once it's up, so not Hyprland: from here because this file loads before
-- Caelestia's own start-up (hyprland/execs.lua), so this runs first and the shell starts with them
hl.on("hyprland.start", function()
    if cpu_apps then
        hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
        hl.env("XWAYLAND_NO_GLAMOR", "1")
    end
end)
return vars
