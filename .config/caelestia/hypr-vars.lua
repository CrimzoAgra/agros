-- Caelestia's variables I change (~/.config/hypr/variables.lua has them all)
local vars = {
    browser = "librewolf",  -- Super+W: Caelestia's is Firefox, which setup leaves out (LibreWolf instead)
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
    -- Clear every notification: Ctrl+Alt+C (Capri, who had it, is on Shift+Space: user/apps.lua)
    kbClearNotifs              = "CTRL + ALT + C",
}

-- Its shortcuts changed in the Settings app (Keyboard page): caelestia-keys.<variable>, a list of shortcuts, in
-- ~/.config/dots/settings.lua (~/.local/bin/dots-settings). One as a plain string: the "mod + 0-9" ones must be.
-- The ones turned off above aren't listed there, so these can't undo them. A value that isn't a list (a hand edit of
-- settings.json) is left alone: an error here, in the first file Caelestia loads and unguarded, would take the whole
-- config down
local ok, settings = pcall(dofile, os.getenv("HOME") .. "/.config/dots/settings.lua")
for key, keys in pairs(ok and type(settings) == "table" and settings or {}) do
    -- (a key that isn't a string, from a hand edit of settings.lua, is skipped too: indexing it errored)
    local var = type(key) == "string" and key:match("^caelestia%-keys%.(kb%w+)$")
    if var and type(keys) == "table" then vars[var] = #keys == 1 and keys[1] or (#keys == 0 and "" or keys) end
end
return vars
