#!/usr/bin/env bash
# lutris-covers' cover checks on made-up pictures: Steam's padded cover is caught, a real one isn't, a corrupt or wide
# one needs a new cover (no network: nothing is downloaded); a turned-down key stops the run
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/.config/dots" "$t/steam/covers"; echo test-key >"$t/.config/dots/steamgriddb.key"
HOME=$t python3 -I - "$here/.local/bin/lutris-covers" "$t" <<'P'
import importlib.machinery, importlib.util, random, sys, types
loader = importlib.machinery.SourceFileLoader("covers", sys.argv[1])
covers = importlib.util.module_from_spec(importlib.util.spec_from_loader("covers", loader))
loader.exec_module(covers)
from gi.repository import GdkPixbuf, GLib
t = sys.argv[2]
def picture(name, w, h, pixel):
    data = bytes(v for y in range(h) for x in range(w) for v in pixel(x, y))
    GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(data), GdkPixbuf.Colorspace.RGB, False, 8, w, h, w * 3).savev(f"{t}/{name}", "png", [], [])
    return f"{t}/{name}"
rnd = random.Random(1)
noise = lambda x, y: [rnd.randrange(256) for _ in range(3)]
# Header art at the top, then each column one colour down to the bottom
padded = picture("steam/covers/padded.png", 300, 450, lambda x, y: noise(x, y) if y < 150 else [x % 256, (x * 3) % 256, 90])
real = picture("steam/covers/real.png", 300, 450, noise)
wide = picture("wide.png", 460, 215, noise)
open(f"{t}/steam/covers/corrupt.jpg", "wb").write(b"\xff\xd8\xff\xe0 not really a jpeg")
item = lambda path: types.SimpleNamespace(get_media_paths=lambda: [types.SimpleNamespace(path=path, exists=True)])
assert covers.padded(padded), "padded cover not caught"
assert not covers.padded(real), "real cover taken for padded"
assert covers.needs_cover(item(padded)) and not covers.needs_cover(item(real))
assert covers.needs_cover(item(wide)), "wide cover kept"
assert covers.needs_cover(item(f"{t}/steam/covers/corrupt.jpg")), "corrupt cover kept"
assert covers.needs_cover(types.SimpleNamespace(get_media_paths=lambda: [])), "no cover kept"
assert covers.same_name("Aerial_Knights Never Yield", "Aerial_Knight's Never Yield") and not covers.same_name("Aerial_Knight's We Never Yield", "Aerial_Knight's Never Yield"), "names matched wrong"
# A key SteamGridDB turns down: the run stops at the first game (not a failed request per game), none marked tried
import os, urllib.error
asked = []
def refused(game):
    asked.append(game["slug"])
    raise urllib.error.HTTPError("https://x", 401, "Unauthorized", {}, None)
covers.find_cover, covers.needs_cover = refused, lambda item: True
sys.modules["lutris.database.games"] = types.SimpleNamespace(get_games=lambda: [{"slug": "a"}, {"slug": "b"}])
sys.modules["lutris.gui.views.store_item"] = types.SimpleNamespace(StoreItem=lambda *a: None)
sys.modules["lutris.services.base"] = types.SimpleNamespace(LutrisCoverartMedium=lambda: None)
covers.main()
assert asked == ["a"] and not os.path.exists(covers.TRIED), asked
P
echo "ok lutris-covers"
