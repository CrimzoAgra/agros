#!/usr/bin/env bash
# lutris-covers' cover checks on made-up pictures: Steam's padded cover is caught, a real one isn't, a corrupt or wide
# one needs a new cover (no network: nothing is downloaded); a turned-down key stops the run, it, offline, 429 and 5xx
# exit 1; a permanent error marks the game tried; an empty cover file doesn't count as one
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
# The game named exactly as it first, of those named alike but for punctuation ("REDACTED" is another game, and its
# search gives it first)
calls = []
def search(path):
    calls.append(path)
    return [{"id": 1, "name": "REDACTED"}, {"id": 2, "name": "[REDACTED]"}] if path.startswith("/search/") else [{"url": "u"}]
covers.api = search
assert covers.find_cover({"service": "egs", "service_id": "x", "name": "[REDACTED]"}) == "u" and calls[-1].startswith("/grids/game/2?"), calls
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
sys.modules["lutris.settings"] = types.SimpleNamespace(COVERART_PATH=f"{t}/coverart")
assert covers.main() == 1, "a turned-down key exited 0"
assert asked == ["a"] and not os.path.exists(covers.TRIED), asked
# Offline: every game asked, none marked tried, and 1 (the wrapper doesn't mark the library checked)
def offline(game):
    asked.append(game["slug"])
    raise urllib.error.URLError("offline")
covers.find_cover, asked[:] = offline, []
assert covers.main() == 1 and asked == ["a", "b"] and not os.path.exists(covers.TRIED), asked
# Too many requests, a server error: as offline, asked again next time
for code in (429, 503):
    def busy(game, code=code):
        asked.append(game["slug"])
        raise urllib.error.HTTPError("https://x", code, "Busy", {}, None)
    covers.find_cover, asked[:] = busy, []
    assert covers.main() == 1 and asked == ["a", "b"] and not os.path.exists(covers.TRIED), (code, asked)
# A permanent error (HTTP 403, a picture that's neither PNG nor JPEG): marked tried, not rerun at every start
def forbidden(game):
    if game["slug"] == "a":
        raise urllib.error.HTTPError("https://x", 403, "Forbidden", {}, None)
    raise ValueError("not a PNG or JPEG")
covers.find_cover = forbidden
assert covers.main() == 0 and open(covers.TRIED).read().split() == ["a", "b"], open(covers.TRIED).read()
# An empty cover file (a download Lutris cut off): asked all the same, not skipped for good; the cover saved and the
# empty one of the other kind taken away (Lutris could pick it)
import contextlib
os.makedirs(f"{t}/coverart", exist_ok=True)
open(f"{t}/coverart/c.jpg", "wb").close()
png = b"\x89PNG\r\n\x1a\n" + b"x" * 10
covers.find_cover = lambda game: "https://x/c.png"
covers.urllib.request.urlopen = lambda *a, **k: contextlib.nullcontext(types.SimpleNamespace(read=lambda: png))
sys.modules["lutris.database.games"] = types.SimpleNamespace(get_games=lambda: [{"slug": "c"}])
assert covers.main() == 0, "a game with an empty cover not asked"
assert open(f"{t}/coverart/c.png", "rb").read() == png and not os.path.exists(f"{t}/coverart/c.jpg"), os.listdir(f"{t}/coverart")
P
echo "ok lutris-covers"
