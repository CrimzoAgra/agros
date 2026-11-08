-- Screens of the Legion Pro 7 laptop (hostname LegionCachy). Loaded by user/monitors.lua on this machine only.

-- Laptop panel: at the bottom, with the 1080-high screen above it starting at 0,0: a screen above one at 0,0 would sit at
-- negative coordinates, and Proton (Wine) games under XWayland then aim the mouse somewhere else than the pointer
-- (monitors.lua). 160 = (1920 - 1600) / 2 centres the panel (2560 / 1.6 wide) under it.
-- OLED, 10-bit; colours left vivid (shown on its wide native gamut; cm = "edid" would make them accurate);
-- variable refresh only in fullscreen (games): on the desktop it can make the OLED flicker
dots.monitor({ output = "eDP-1", mode = "2560x1600@240", position = "160x1080", scale = 1.6, bitdepth = 10, vrr = 2 })

-- Samsung LF27T450F: its best refresh rate, above the laptop, centred
dots.monitor({
    output = "desc:Samsung Electric Company LF27T450F",
    mode = "1920x1080@74.97",
    position = "0x0",
    scale = 1,
})
