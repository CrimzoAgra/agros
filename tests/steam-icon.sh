#!/usr/bin/env bash
# steam-icon: a Steam game with no icon gets one from Steam's library cache (its hash-named .jpg, not its banners), as
# steam_icon_<id>; one it already has is left alone; nothing cached, none and no error. From another Steam folder when
# given (Flathub's). game-focus makes them through it
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
grep -q 'f"{HELPERS}/steam-icon"' "$here/.local/bin/game-focus" || fail "game-focus doesn't make game icons through steam-icon"
HOME=$t python3 -I - "$here/.local/bin/steam-icon" "$t" <<'P' || fail "steam-icon made the wrong icons"
import os, subprocess, sys
tool, t = sys.argv[1:]
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
def cached(root, gid):
    cache = f"{root}/appcache/librarycache/{gid}"
    os.makedirs(cache)
    GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 32, 32).savev(f"{cache}/{'a' * 40}.jpg", "jpeg", [], [])
    GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 460, 215).savev(f"{cache}/header.jpg", "jpeg", [], [])
run = lambda *a: subprocess.run([tool, *a]).returncode
cached(f"{t}/.local/share/Steam", "42")
assert run("42") == 0
icon = f"{t}/.local/share/icons/hicolor/32x32/apps/steam_icon_42.png"
assert GdkPixbuf.Pixbuf.new_from_file(icon).get_width() == 32, "icon not made from the cache's small icon"
mtime = os.path.getmtime(icon)
assert run("42") == 0 and os.path.getmtime(icon) == mtime, "an icon it had was made again"
assert run("43") == 1 and not os.path.exists(icon.replace("42", "43")), "an icon made with nothing cached"
cached(f"{t}/flat", "44")
assert run("44", f"{t}/flat") == 0 and os.path.exists(icon.replace("42", "44")), "not made from the Steam folder given"
P
ok_line steam-icon
