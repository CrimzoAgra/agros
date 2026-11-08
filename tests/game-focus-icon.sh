#!/usr/bin/env bash
# A Steam game with no icon gets one from Steam's library cache (its hash-named .jpg, not its banners), as
# steam_icon_<id>; one it already has is left alone
set -euo pipefail
. "$(dirname "$0")/lib.sh"
HOME=$t python3 -I - "$here/.local/bin/game-focus" "$t" <<'P'
import importlib.machinery, importlib.util, os, sys
path, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("gf", path)
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
cache = f"{t}/.local/share/Steam/appcache/librarycache/42"
os.makedirs(cache)
GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 32, 32).savev(f"{cache}/{'a' * 40}.jpg", "jpeg", [], [])
GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 460, 215).savev(f"{cache}/header.jpg", "jpeg", [], [])
gf.game_icon("42")
icon = f"{t}/.local/share/icons/hicolor/32x32/apps/steam_icon_42.png"
assert GdkPixbuf.Pixbuf.new_from_file(icon).get_width() == 32, "icon not made from the cache's small icon"
mtime = os.path.getmtime(icon)
gf.game_icon("42")
assert os.path.getmtime(icon) == mtime, "an icon it had was made again"
gf.game_icon("43")  # nothing cached for it: no icon, no error
assert not os.path.exists(icon.replace("42", "43"))
P
echo "ok game-focus-icon"
