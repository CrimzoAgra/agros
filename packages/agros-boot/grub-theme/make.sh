#!/usr/bin/env bash
# Makes AgrOS's GRUB theme's pictures and fonts (committed beside it; run again after changing the look):
# the AgrOS banner (above the menu, on the theme's #121318), the selection pill, the logo as the entries' icon (Windows
# and the firmware with their own), Rubik (Caelestia's font) as GRUB fonts
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
rsvg-convert -w 460 "$repo/docs/images/agros-banner.svg" -o "$here/banner.png"
rsvg-convert -w 32 -h 32 "$repo/.local/share/icons/hicolor/scalable/apps/agros-logo.svg" -o "$t/logo.png"
python3 -I - "$t" "$here" <<'P'
import sys
from PIL import Image, ImageDraw
t, out = sys.argv[1:]
# The highlight: a pill, its round ends (w, e) and middle (c), the logo's lavender, faint
fill, h, r = (0xbe, 0xc4, 0xee, 46), 44, 22
pill = Image.new("RGBA", (2 * r + 1, h)); ImageDraw.Draw(pill).rounded_rectangle((0, 0, 2 * r, h - 1), r, fill=fill)
pill.crop((0, 0, r, h)).save(f"{out}/select_w.png"); pill.crop((r, 0, r + 1, h)).save(f"{out}/select_c.png")
pill.crop((r + 1, 0, 2 * r + 1, h)).save(f"{out}/select_e.png")
# Windows' and the firmware settings' icons, drawn like the logo: lavender lines, 32 px (drawn at 4x, then scaled down
# for smooth edges): Windows' four panes, the firmware a chip with its pins
lav, k = (0xbe, 0xc4, 0xee, 255), 4
def icon(name, draw):
    im = Image.new("RGBA", (32 * k, 32 * k)); draw(ImageDraw.Draw(im))
    im.resize((32, 32), Image.LANCZOS).save(f"{t}/{name}.png")
icon("windows", lambda d: [d.rectangle((x * k, y * k, (x + 13) * k, (y + 13) * k), outline=lav, width=10)
                           for x in (2, 17) for y in (2, 17)])
def chip(d):
    d.rounded_rectangle((7 * k, 7 * k, 25 * k, 25 * k), 2 * k, outline=lav, width=10)
    d.rectangle((12 * k, 12 * k, 20 * k, 20 * k), fill=lav)
    for p in (11, 16, 21):
        d.line((p * k, 1 * k, p * k, 7 * k), fill=lav, width=10); d.line((p * k, 25 * k, p * k, 31 * k), fill=lav, width=10)
        d.line((1 * k, p * k, 7 * k, p * k), fill=lav, width=10); d.line((25 * k, p * k, 31 * k, p * k), fill=lav, width=10)
icon("efi", chip)
P
mkdir -p "$here/icons"
for c in cachyos arch gnu-linux linux; do cp "$t/logo.png" "$here/icons/$c.png"; done
# (GRUB's class names: os-prober's Windows entry is "windows"; "efi" is 31_efi_bootnext's for an unnamed entry. GRUB
# 2.16's 30_uefi-firmware gives its entry no class, so no icon there)
cp "$t/windows.png" "$t/efi.png" "$here/icons/"
font=$(fc-match -f '%{file}' 'Rubik:weight=regular')
grub-mkfont -s 22 -n Rubik -o "$here/rubik-22.pf2" "$font"
grub-mkfont -s 18 -n Rubik -o "$here/rubik-18.pf2" "$font"
