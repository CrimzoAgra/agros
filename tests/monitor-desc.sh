#!/usr/bin/env bash
# Monitor rules name a screen by make and model only (no serial number in the repo): dots.monitor finds the connected
# screen whose description starts with it; one not connected keeps its rule as written
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip monitor-desc (no lua)"; exit 0; }
out=$(cd "$here" && HOME=$t lua -e '
hl = { get_monitors = function() return { { name = "HDMI-A-1", description = "Samsung Electric Company C24F390 SERIAL1" } } end,
       monitor = function(r) io.write(r.output, "\n") end, bind = function() end,
       dsp = { exec_cmd = function() end } }
dots = { setting = function() end, settings = function() return {} end }
dofile(".config/caelestia/user/monitors.lua")
dots.monitor({ output = "desc:Samsung Electric Company C24F390" })
dots.monitor({ output = "desc:Samsung Electric Company C24F390" })
dots.monitor({ output = "desc:Other Make X" })')
grep -qx "desc:Samsung Electric Company C24F390 SERIAL1" <<<"$out" || { echo "FAIL: the connected screen wasn't matched: $out"; exit 1; }
# (two rules for one model, one screen: the second keeps its rule as written)
[[ $(grep -cx "desc:Samsung Electric Company C24F390" <<<"$out") == 1 ]] || { echo "FAIL: one screen taken by two rules: $out"; exit 1; }
grep -qx "desc:Other Make X" <<<"$out" || { echo "FAIL: a screen not connected lost its rule: $out"; exit 1; }
# This machine's screens file with a mistake in it: a config error, but any other screen (all of them, here) still
# gets a rule
mkdir -p "$t/.config/caelestia/user/hosts"
echo 'error("a mistake")' >"$t/.config/caelestia/user/hosts/$(cat /proc/sys/kernel/hostname).lua"
out=$(cd "$here" && HOME=$t lua -e '
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
hl = { get_monitors = function() return {} end, monitor = function(r) io.write("rule [", r.output, "]\n") end }
dots = { setting = function() end, settings = function() return {} end }
io.write(pcall(dofile, ".config/caelestia/user/monitors.lua") and "loaded\n" or "error\n")')
[[ $out == $'rule []\nerror' ]] || { echo "FAIL: a broken host file left screens without a rule: $out"; exit 1; }
# (dots.setting / dots.settings: hypr-user.lua's, with no Settings app changes)
# A screen with no rule of its own: its preferred resolution at its fastest rate there (not another resolution's
# faster one, not the preferred 60); one this machine's host file names: left to that rule; a VM's: the kernel's
# preferred mode (its window's size; Hyprland's own list is the one it had at connect), "preferred" without one, never
# a fixed rate (one rate there, 60 being its preferred 59.94)
echo 'dots.monitor({ output = "desc:Named One", mode = "1920x1080@60", position = "160x1080" })' >"$t/.config/caelestia/user/hosts/$(cat /proc/sys/kernel/hostname).lua"
# (a /sys of its own: CI runs in a VM, whose real Virtual-1 has its own size)
mkdir -p "$t/sys"
screens() { cd "$here" && SYSFS=$t/sys HOME=$t lua -e '
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
local modes = { { width = 1920, height = 1080, refresh_rate = 60.0, preferred = true },
                { width = 1920, height = 1080, refresh_rate = 143.98, preferred = false },
                { width = 2560, height = 1440, refresh_rate = 75.0, preferred = false },
                { width = 1280, height = 720, refresh_rate = 240.0, preferred = false } }
-- (Hyprland 0.57: a screen that is off listed only with { all = true })
local function listed(ms) return function(o)
    local r = {}
    for _, m in ipairs(ms) do if o and o.all or m.enabled ~= false then r[#r + 1] = m end end
    return r
end end
hl = { get_monitors = listed({ { name = "DP-1", description = "Fast One", available_modes = modes },
                                          { name = "DP-4", description = "Off One", available_modes = modes, enabled = false },
                                          { name = "DP-2", description = "Named One", available_modes = modes },
                                          { name = "Virtual-1", description = "", available_modes = {
                                              { width = 2258, height = 1359, refresh_rate = 59.94, preferred = true },
                                              { width = 2258, height = 1359, refresh_rate = 60.0, preferred = false },
                                              { width = 4096, height = 2160, refresh_rate = 60.0, preferred = false } } } }),
       monitor = function(r) io.write(r.output, " ", tostring(r.mode), "\n") end, bind = function() end,
       dsp = { exec_cmd = function() end } }
dots = { setting = function() end, settings = function() return {} end }
dofile(".config/caelestia/user/monitors.lua")'; }
out=$(screens)
grep -qx "DP-1 1920x1080@143.98" <<<"$out" || fail "a screen with no rule of its own not at its fastest rate: $out"
grep -qx "DP-4 1920x1080@143.98" <<<"$out" || fail "a screen that's off got no rule (back on: not at its fastest rate): $out"
grep -qx "desc:Named One 1920x1080@60" <<<"$out" && ! grep -q "^DP-2 " <<<"$out" || fail "a screen the host file names got another rule: $out"
[[ $(grep "^Virtual-1 " <<<"$out") == "Virtual-1 preferred" ]] ||
    fail "a VM's screen with no mode from the kernel not left at preferred: $out"
mkdir -p "$t/sys/class/drm/card0-Virtual-1"; printf '1594x884\n4096x2160\n' >"$t/sys/class/drm/card0-Virtual-1/modes"
[[ $(screens | grep "^Virtual-1 ") == "Virtual-1 1594x884" ]] ||
    fail "a VM's screen not at the kernel's preferred mode (its window's size): $(screens)"
# The Settings app's Screens page (screens.<description>.<field>): over the rule that applied, what's left empty kept
# (the fastest rate here, also over a mode the screen doesn't have); the main screen at 0x0 and the others to its right;
# never every screen off. EXTRA: more screens: one off but listed (with all), one the host file places, one with no
# description (its settings by its name)
settings() { cd "$here" && HOME=$t EXTRA=${1:-} lua -e '
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
local mine = { ["screens.Fast One.scale"] = "1.5", ["screens.Fast One.enabled"] = false, ["screens.main"] = "Other One",
               ["screens.Other One.enabled"] = false, ["screens.Other One.mode"] = 7,
               ["screens.Fast One.mode"] = "3840x2160@60.00", ["screens.Off One.mode"] = "1920x1080@60.00",
               ["screens.Off One.scale"] = "0", ["screens.Off One.position"] = "left of it",
               ["screens.DP-5.scale"] = "1.25", ["screens.DP-5.enabled"] = false, ["screens.Other One.hdr"] = "on", ["screens.Other One.brightness"] = "300",
               ["screens.Other One.saturation"] = "120", ["screens.Other One.black"] = "0.05",
               ["screens.Fast One.hdr"] = "" }
local list = { { name = "DP-1", description = "Fast One", available_modes = {
                   { width = 1920, height = 1080, refresh_rate = 60.0, preferred = true },
                   { width = 1920, height = 1080, refresh_rate = 143.98 } } },
               { name = "DP-3", description = "Other One", available_modes = {} } }
if os.getenv("EXTRA") ~= "" then
    list[#list + 1] = { name = "DP-4", description = "Off One", enabled = false, available_modes = {
                          { width = 1920, height = 1080, refresh_rate = 60.0, preferred = true } } }
    list[#list + 1] = { name = "DP-2", description = "Named One", available_modes = {} }
    list[#list + 1] = { name = "DP-5", description = "", available_modes = {} }
end
hl = { get_monitors = function(o)  -- (Hyprland 0.57: a screen that is off listed only with { all = true })
           local r = {}
           for _, m in ipairs(list) do if o and o.all or m.enabled ~= false then r[#r + 1] = m end end
           return r
       end,
       monitor = function(r)
           io.write(r.output, " ", tostring(r.mode), " ", tostring(r.scale), " ", tostring(r.position), " ",
                    tostring(r.disabled), "\n")
           if r.cm then io.write("cm ", r.output, " ", r.cm, " ", tostring(r.bitdepth), " ", tostring(r.sdr_eotf), " ", tostring(r.sdr_min_luminance), " ", tostring(r.sdr_max_luminance), " ", tostring(r.sdrsaturation), "\n") end
       end, bind = function() end, dsp = { exec_cmd = function() end } }
dots = { setting = function(k) return mine[k] end, settings = function() return mine end }
dofile(".config/caelestia/user/monitors.lua")'; }
out=$(settings)
grep -qx "desc:Fast One 1920x1080@143.98 1.5 auto-right true" <<<"$out" ||
    fail "a screen's settings not over its rule (fastest rate kept, scale, to the main one's right, off): $out"
# (a mode that isn't text, from a hand edit: left out; the second screen off would be every screen: it stays on)
grep -qx "desc:Other One preferred auto 0x0 nil" <<<"$out" || fail "the main screen not at 0x0, or every screen off: $out"
# (HDR always: 10-bit, HDR colour, SDR as an SDR screen shows it, its white as set; Automatic, empty: Hyprland's own, no colour mode set)
grep -qx "cm desc:Other One hdr 10 gamma22 0.05 300 1.2" <<<"$out" && ! grep -q "^cm desc:Fast One" <<<"$out" || fail "HDR not as set: $out"
out=$(settings 1)
# (and a scale and position from a hand edit that Hyprland can't take left out: the rule that applied, to the main's right)
grep -qx "desc:Off One 1920x1080@60.00 auto auto-right nil" <<<"$out" ||
    fail "a screen that's off but listed lost its settings, or got a scale or position that isn't one: $out"
grep -qE "^desc:( |$)" <<<"$out" && fail "a screen with no description got a desc: rule matching every screen: $out"
# (one with no description, a VM's: its settings by its connector's name, as the Settings app keys them)
grep -qx "DP-5 preferred 1.25 auto-right true" <<<"$out" || fail "a screen with no description lost its settings: $out"
# (the host file's position kept, not moved to the main one's right)
grep -q "^desc:Named One .* auto-right" <<<"$out" && fail "the host file's position dropped for the main one's right: $out"
# The lid and the Settings app's "On" agree (one place decides): docked, lid shut, the other screen turned off stays on
# (both were dark), whether the lid closed before the load or after; the lid opened, a panel turned off in the Settings
# app stays off. lid: the lid at the load; the rules after the load (or the switch) as "<output> <disabled>"
lid() { cd "$here" && HOME=$t LID=$1 SETS=$2 MAIN=${3:-} REV=${4:-} lua -e '
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
local real = io.popen
io.popen = function(c)
    if c:find("lid", 1, true) then return { read = function() return "state:      " .. os.getenv("LID") end, close = function() end } end
    return real(c)
end
local mine = {}
for k in os.getenv("SETS"):gmatch("[^,]+") do mine["screens." .. k .. ".enabled"] = false end
if os.getenv("MAIN") ~= "" then mine["screens.main"] = os.getenv("MAIN") end
local log = {}
local list = { { name = "eDP-1", description = "Panel" }, { name = "DP-1", description = "Ext" } }
-- (a third screen already off: Hyprland lists it only with all)
if mine["screens.Dark.enabled"] == false then list[3] = { name = "DP-2", description = "Dark", enabled = false } end
if os.getenv("REV") ~= "" then list = { list[3] or list[2], list[3] and list[2] or list[1], list[3] and list[1] } end
hl = { get_monitors = function(o)
           local r = {}
           for _, m in ipairs(list) do if o and o.all or m.enabled ~= false then r[#r + 1] = m end end
           return r
       end,
       monitor = function(r) log[#log + 1] = r.output .. " " .. tostring(r.disabled) end, bind = function() end,
       dsp = { exec_cmd = function() end } }
dots = { setting = function(k) return mine[k] end, settings = function() return mine end }
dofile(".config/caelestia/user/monitors.lua")
io.write(table.concat(log, "\n"), "\n--\n"); log = {}
dots.lid(os.getenv("LID") == "open")
io.write(table.concat(log, "\n"), "\n")'; }
# (the screen's rules by its name and its description: the last one says)
last() { grep -E "^(DP-1|desc:Ext) " <<<"$1" | tail -1; }
out=$(lid open Ext)
[[ $(last "${out%%--*}") == "desc:Ext true" && $(last "${out#*--}") == "desc:Ext false" ]] ||
    fail "the lid closed with the other screen turned off: that one not on again: $out"
out=$(lid closed Ext)
grep -qE "^(DP-1|desc:Ext) true" <<<"${out%%--*}" && fail "lid shut at the load: the other screen turned off too: $out"
grep -q "^eDP-1 true" <<<"${out%%--*}" || fail "lid shut at the load: the panel not off: $out"
out=$(lid closed Panel)
grep -qE "^(eDP-1|desc:Panel) false" <<<"${out#*--}" && fail "the lid opened: a panel turned off in the Settings app on again: $out"
out=$(lid closed "")
grep -q "^eDP-1 false" <<<"${out#*--}" || fail "the lid opened: the panel not on again: $out"
# Every screen set off (one listed only with all): the one left on is the main one, else the laptop's panel, whatever
# order Hyprland lists them in
for rev in "" 1; do
    out=$(lid open Panel,Ext,Dark "" "$rev")
    [[ $(grep -cE "^desc:(Ext|Dark) true" <<<"${out%%--*}") == 2 ]] && ! grep -q "^desc:Panel true" <<<"${out%%--*}" ||
        fail "every screen off: not the panel kept on (order ${rev:-as listed}): $out"
    out=$(lid open Panel,Ext,Dark Ext "$rev")
    grep -q "^desc:Panel true" <<<"${out%%--*}" && ! grep -q "^desc:Ext true" <<<"${out%%--*}" ||
        fail "every screen off: not the main one kept on (order ${rev:-as listed}): $out"
done
echo "ok monitor-desc"
