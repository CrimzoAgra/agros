#!/usr/bin/env bash
# agros-thunar-usage: its two Thunar plugins build as its PKGBUILD builds them (every symbol they use found: linked with
# -z defs) and have the three functions Thunar looks for, without which Thunar refuses to load one; Set as wallpaper
# offered for the pictures Caelestia takes only
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
pkg-config --exists thunarx-3 || { echo "skip thunar-usage (no Thunar headers)"; exit 0; }
cp "$here"/packages/agros-thunar-usage/*.c "$t/"
# shellcheck disable=SC1091  # (the PKGBUILD's build(), run where its source is)
(cd "$t" && . "$here/packages/agros-thunar-usage/PKGBUILD" && CFLAGS="-Wall -Werror" LDFLAGS='' build) >"$t/out" 2>&1 ||
    fail "doesn't build: $(tail -3 "$t/out")"
for so in agros-thunar-usage agros-thunar-wallpaper; do
    for s in thunar_extension_initialize thunar_extension_shutdown thunar_extension_list_types; do
        grep -qw "$s" <<<"$(nm -D --defined-only "$t/$so.so")" || fail "$so: $s not exported"
    done
done
# (Caelestia's list: caelestia/utils/wallpaper.py's is_valid_image)
r=$(python3 -I -c '
import ctypes, sys
f = ctypes.CDLL(sys.argv[1]).agros_wallpaper_takes
f.argtypes = [ctypes.c_char_p]
for p in sys.argv[2:]:
    print(p, f(p.encode()))
' "$t/agros-thunar-wallpaper.so" /a/b.png /a/B.JPG /a/c.jpeg /a/d.webp /a/e.tif /a/f.tiff /a/g.gif /a/h.svg /a/i.bmp \
    /a/png /a.png/j /a/k.png.txt)
want=$'/a/b.png 1\n/a/B.JPG 1\n/a/c.jpeg 1\n/a/d.webp 1\n/a/e.tif 1\n/a/f.tiff 1\n/a/g.gif 1\n/a/h.svg 0\n/a/i.bmp 0\n/a/png 0\n/a.png/j 0\n/a/k.png.txt 0'
[[ $r == "$want" ]] || fail "Set as wallpaper offered for the wrong files: $r"
echo "ok thunar-usage"
