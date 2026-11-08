#!/usr/bin/env bash
# Monitor rules name a screen by make and model only (no serial number in the repo): dots.monitor finds the connected
# screen whose description starts with it; one not connected keeps its rule as written
set -euo pipefail
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip monitor-desc (no lua)"; exit 0; }
out=$(cd "$here" && HOME=$t lua -e '
hl = { get_monitors = function() return { { name = "HDMI-A-1", description = "Samsung Electric Company C24F390 SERIAL1" } } end,
       monitor = function(r) io.write(r.output, "\n") end, bind = function() end,
       dsp = { exec_cmd = function() end } }
dots = {}
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
dots = {}
io.write(pcall(dofile, ".config/caelestia/user/monitors.lua") and "loaded\n" or "error\n")')
[[ $out == $'rule []\nerror' ]] || { echo "FAIL: a broken host file left screens without a rule: $out"; exit 1; }
# A screen with no rule of its own: its preferred resolution at its fastest rate there (not another resolution's
# faster one, not the preferred 60); one this machine's host file names: left to that rule; a VM's (one rate there,
# 60 being its preferred 59.94): no rule of its own, so "preferred" follows its window's size
echo 'dots.monitor({ output = "desc:Named One", mode = "1920x1080@60" })' >"$t/.config/caelestia/user/hosts/$(cat /proc/sys/kernel/hostname).lua"
out=$(cd "$here" && HOME=$t lua -e '
package.path = os.getenv("HOME") .. "/.config/caelestia/?.lua;" .. package.path
local modes = { { width = 1920, height = 1080, refresh_rate = 60.0, preferred = true },
                { width = 1920, height = 1080, refresh_rate = 143.98, preferred = false },
                { width = 2560, height = 1440, refresh_rate = 75.0, preferred = false },
                { width = 1280, height = 720, refresh_rate = 240.0, preferred = false } }
hl = { get_monitors = function() return { { name = "DP-1", description = "Fast One", available_modes = modes },
                                          { name = "DP-2", description = "Named One", available_modes = modes },
                                          { name = "Virtual-1", description = "", available_modes = {
                                              { width = 2258, height = 1359, refresh_rate = 59.94, preferred = true },
                                              { width = 2258, height = 1359, refresh_rate = 60.0, preferred = false },
                                              { width = 4096, height = 2160, refresh_rate = 60.0, preferred = false } } } } end,
       monitor = function(r) io.write(r.output, " ", tostring(r.mode), "\n") end, bind = function() end,
       dsp = { exec_cmd = function() end } }
dots = {}
dofile(".config/caelestia/user/monitors.lua")')
grep -qx "DP-1 1920x1080@143.98" <<<"$out" || fail "a screen with no rule of its own not at its fastest rate: $out"
grep -qx "desc:Named One 1920x1080@60" <<<"$out" && ! grep -q "^DP-2 " <<<"$out" || fail "a screen the host file names got another rule: $out"
! grep -q "^Virtual-1 " <<<"$out" || fail "a screen with one rate got a fixed mode (a VM's then can't follow its window): $out"
echo "ok monitor-desc"
