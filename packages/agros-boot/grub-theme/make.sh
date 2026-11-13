#!/usr/bin/env bash
# Makes AgrOS's GRUB theme's pictures and fonts (committed beside it; run again after changing the look):
# the AgrOS banner (above the menu, on the theme's #121318), the selection pill, the logo as the entries' icon, Rubik
# (Caelestia's font) as GRUB fonts
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
P
mkdir -p "$here/icons"
for c in cachyos arch gnu-linux linux; do cp "$t/logo.png" "$here/icons/$c.png"; done
font=$(fc-match -f '%{file}' 'Rubik:weight=regular')
grub-mkfont -s 22 -n Rubik -o "$here/rubik-22.pf2" "$font"
grub-mkfont -s 18 -n Rubik -o "$here/rubik-18.pf2" "$font"
