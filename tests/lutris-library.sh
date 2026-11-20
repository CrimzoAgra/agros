#!/usr/bin/env bash
# lutris-library and Battle.net: signed out, none of Lutris's built-in list of every Blizzard game joins the library
# (and an older run's are taken out); signed in, the account's games join, ones gone from it leave; installed ones stay.
# The store launchers: listed under Launchers (installed or not, one entry each), unhidden; Steam's installed, opening
# the system's Steam, else Flathub's
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
export HOME=$t XDG_DATA_HOME=$t/.local/share XDG_CACHE_HOME=$t/.cache XDG_CONFIG_HOME=$t/.config
# Steam installed on the system: a stand-in first on the PATH (its Launchers entry opens it, no install)
mkdir -p "$t/bin" && printf '#!/bin/sh\n' >"$t/bin/steam" && chmod +x "$t/bin/steam" && export PATH="$t/bin:$PATH"
mkdir -p "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
python3 -I - <<'P'
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0")
from lutris.database.schema import syncdb
from lutris import settings
import sqlite3
syncdb()
db = sqlite3.connect(settings.DB_PATH)
with db:
    db.executemany("INSERT INTO service_games (service, appid, name, slug) VALUES ('battlenet', ?, ?, ?)",
                   [("s2", "StarCraft II", "starcraft-ii"), ("d3", "Diablo III", "diablo-iii")])
    db.execute("INSERT INTO games (name, slug, installed, service, service_id) VALUES ('Old', 'old', 0, 'battlenet', 'w1')")
    db.execute("INSERT INTO games (name, slug, runner, installed, service, service_id) VALUES ('Mine', 'mine', 'wine', 1, 'battlenet', 'hsb')")
    # A store launcher installed, and hidden by an older run
    db.execute("INSERT INTO games (name, slug, runner, installed) VALUES ('EA App', 'ea-app', 'wine', 1)")
    db.execute("INSERT INTO categories (name) VALUES ('.hidden')")
    db.execute("INSERT INTO games_categories (game_id, category_id) SELECT g.id, c.id FROM games g, categories c WHERE g.slug = 'ea-app' AND c.name = '.hidden'")
    # A catalogue source (Flathub): not games you own
    db.execute("INSERT INTO service_games (service, appid, name, slug) VALUES ('flathub', 'org.x.App', 'App', 'app')")
P
q() { python3 -Ic 'import sqlite3, sys; print(",".join(sorted(r[0] for r in sqlite3.connect(sys.argv[1]).execute("SELECT service_id FROM games WHERE service = '"'battlenet'"'"))))' "$t/.local/share/lutris/pga.db"; }
run() { python3 -I "$here/.local/bin/lutris-library" >/dev/null 2>&1 || { echo "FAIL: lutris-library failed"; python3 -I "$here/.local/bin/lutris-library"; exit 1; }; }
run
[[ $(q) == hsb ]] || { echo "FAIL: signed out, Battle.net games are $(q) (want only the installed hsb)"; exit 1; }
python3 -I - "$t/.local/share/lutris/pga.db" <<'P' || { echo "FAIL: the store launchers aren't listed under Launchers as they should be"; exit 1; }
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
by_category = lambda name: sorted(s for (s,) in db.execute("SELECT g.slug FROM games g JOIN games_categories gc ON gc.game_id = g.id JOIN categories c ON c.id = gc.category_id WHERE c.name = ?", (name,)))
assert by_category("Launchers") == ["battlenet", "ea-app", "epic-games-store", "gog-galaxy", "rockstar-games-launcher", "steam", "ubisoft-connect"], by_category("Launchers")
assert by_category(".hidden") == [], by_category(".hidden")
assert db.execute("SELECT count(*) FROM games WHERE slug = 'ea-app' AND installed = 1").fetchone() == (1,)
assert db.execute("SELECT count(*) FROM games WHERE slug = 'gog-galaxy' AND installed = 0 AND service IS NULL").fetchone() == (1,)
P
echo "[]" >"$t/.cache/lutris/bnet-owned.json"
run
[[ $(q) == hsb ]] || { echo "FAIL: Lutris without the sign-in patch, Battle.net games are $(q) (want only hsb)"; exit 1; }
mkdir -p "$t/.cache/lutris-overlay/lutris/services"; echo '# lutris-owned' >"$t/.cache/lutris-overlay/lutris/services/battlenet.py"
run
[[ $(q) == d3,hsb,s2 ]] || { echo "FAIL: signed in, Battle.net games are $(q) (want d3,hsb,s2)"; exit 1; }
python3 -Ic 'import sqlite3, sys; sys.exit(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM games WHERE service = '"'flathub'"'").fetchone()[0])' "$t/.local/share/lutris/pga.db" ||
    { echo "FAIL: a Flathub catalogue entry was added to the library"; exit 1; }
# A failed rebuild: plain Lutris runs (every Blizzard game again), the old patched copy still there
touch "$t/.cache/lutris-overlay.failed"
run
[[ $(q) == hsb ]] || { echo "FAIL: after a failed Lutris rebuild, Battle.net games are $(q) (want only hsb)"; exit 1; }
rm "$t/.cache/lutris-overlay.failed"
run
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("DELETE FROM service_games WHERE appid = '"'d3'"'"); c.commit()' "$t/.local/share/lutris/pga.db"
run
[[ $(q) == hsb,s2 ]] || { echo "FAIL: a game gone from the account stayed: $(q)"; exit 1; }
# A reload under way (Lutris emptied its Battle.net list to refill it): nothing taken out
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("DELETE FROM service_games WHERE service = '"'battlenet'"'"); c.commit()' "$t/.local/share/lutris/pga.db"
run
[[ $(q) == hsb,s2 ]] || { echo "FAIL: games taken out while the Battle.net list was being reloaded: $(q)"; exit 1; }
# Lutris never run (agros-welcome on a fresh install): its folders and database made, the launchers listed for its first window
rm -rf "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
run
# (with no ~/.config/lutris, Lutris keeps its configs in its data folder)
[[ -f $t/.local/share/lutris/pga.db && -d $t/.local/share/lutris/coverart && -d $t/.local/share/lutris/games && -d $t/.cache/lutris/installer ]] ||
    { echo "FAIL: Lutris's folders and database weren't made"; ls -R "$t/.local/share" "$t/.cache"; exit 1; }
python3 -I - "$t/.local/share/lutris/pga.db" <<'P' || { echo "FAIL: in a database made by the script the launchers aren't listed"; exit 1; }
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
assert db.execute("SELECT count(*) FROM games g JOIN games_categories gc ON gc.game_id = g.id JOIN categories c ON c.id = gc.category_id WHERE c.name = 'Launchers'").fetchone() == (7,)
assert db.execute("SELECT count(*) FROM games WHERE installed = 0 AND runner IS NULL").fetchone() == (6,)
# Steam: installed, opening the system's
import os
((runner, config),) = db.execute("SELECT runner, configpath FROM games WHERE slug = 'steam' AND installed = 1").fetchall()
assert runner == "linux", runner
assert "/bin/steam" in open(os.path.expanduser(f"~/.local/share/lutris/games/{config}.yml")).read()
P
# The covers bundled in /etc/skel (lutris.net has none for them): copied in when missing, one you have kept
mkdir -p "$t/skel/.local/share/lutris/coverart"; echo bundled >"$t/skel/.local/share/lutris/coverart/bundled-only.png"
echo bundled >"$t/skel/.local/share/lutris/coverart/mine.jpg"; echo yours >"$t/.local/share/lutris/coverart/mine.png"
AGROS_SKEL=$t/skel run
[[ $(cat "$t/.local/share/lutris/coverart/bundled-only.png" 2>/dev/null) == bundled ]] || { echo "FAIL: a bundled cover not copied in"; exit 1; }
[[ ! -e $t/.local/share/lutris/coverart/mine.jpg && $(cat "$t/.local/share/lutris/coverart/mine.png") == yours ]] ||
    { echo "FAIL: a bundled cover taken over one you have"; exit 1; }
# Only Flathub's Steam (a stand-in flatpak, no steam on the PATH): its entry installed too, opening it with flatpak
rm -rf "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
mkdir -p "$t/flat" && ln -s "$(command -v python3)" "$t/flat/python3"
printf '#!/bin/sh\n[ "$*" = "info com.valvesoftware.Steam" ]\n' >"$t/flat/flatpak" && chmod +x "$t/flat/flatpak"
PATH=$t/flat run
python3 -I - "$t/.local/share/lutris/pga.db" "$t/flat/flatpak" <<'P' || { echo "FAIL: with only Flathub's Steam its entry isn't installed opening it"; exit 1; }
import os, sqlite3, sys, yaml
((config,),) = sqlite3.connect(sys.argv[1]).execute("SELECT configpath FROM games WHERE slug = 'steam' AND installed = 1 AND runner = 'linux'").fetchall()
game = yaml.safe_load(open(os.path.expanduser(f"~/.local/share/lutris/games/{config}.yml")))["game"]
assert game == {"exe": sys.argv[2], "args": "run com.valvesoftware.Steam"}, game
P
# Flathub's Steam where newer versions of it keep it (~/.var/app/<id>/.local/share/Steam, no data/Steam): its installed
# game joins the library (in Lutris's Steam list already: no cover download)
lib=$t/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps
mkdir -p "$lib/common/Game"
printf '"AppState"
{
	"appid"		"42"
	"name"		"Flat Game"
	"StateFlags"		"4"
	"installdir"		"Game"
}
' >"$lib/appmanifest_42.acf"
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("INSERT INTO service_games (service, appid, name, slug) VALUES ('"'steam', '42', 'Flat Game', 'flat-game'"')"); c.commit()' "$t/.local/share/lutris/pga.db"
PATH=$t/flat run
python3 -Ic 'import sqlite3, sys; sys.exit(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM games WHERE service = '"'steam'"' AND service_id = '"'42'"' AND installed = 1").fetchone()[0] != 1)' "$t/.local/share/lutris/pga.db" ||
    { echo "FAIL: Flathub's Steam's installed game didn't join the library"; exit 1; }
# Marked uninstalled by a sync while its drive wasn't mounted (Lutris's entry kept): installed again once it's back
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("UPDATE games SET installed = 0, installer_slug = '"'steam-42'"' WHERE service_id = '"'42'"'"); c.commit()' "$t/.local/share/lutris/pga.db"
PATH=$t/flat run
python3 -Ic 'import sqlite3, sys; sys.exit(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM games WHERE service = '"'steam'"' AND service_id = '"'42'"' AND installed = 1 AND runner = '"'steam'"'").fetchone()[0] != 1)' "$t/.local/share/lutris/pga.db" ||
    { echo "FAIL: a Steam game back from an unmounted drive is still not installed"; exit 1; }
# Epic: a game joins, its add-ons (a DLC, a map) don't, and an add-on added by an older run is hidden. Lutris's library
# sync's entries (your lutris.net account's, no store id): given their id back, not added again beside it; the one this
# script had added gives way; an add-on among them hidden
python3 -I - "$t/.local/share/lutris/pga.db" <<'P2'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executemany("INSERT INTO service_games (service, appid, name, slug, details) VALUES ('egs', ?, ?, ?, ?)", [
    ("game", "Epic Game", "epic-game", json.dumps({"categories": [{"path": "games"}]})),
    ("dlc", "Some DLC", "some-dlc", json.dumps({"mainGameItem": {"id": "x"}, "categories": [{"path": "dlc"}]})),
    ("map", "Berlin", "berlin", json.dumps({"categories": [{"path": "addons"}]})),
    ("synced", "Synced Game", "synced-game", json.dumps({"categories": [{"path": "games"}]})),
    ("route", "Dubai", "dubai", json.dumps({"categories": [{"path": "addons"}]})),
    # (named apart by Epic and by Lutris's slug of its name, your other PC's: k-ln for Köln)
    ("koln", "Schnellfahrstrecke Köln-Aachen", "schnellfahrstrecke-koln-aachen",
     json.dumps({"categories": [{"path": "addons"}]}))])
c.execute("INSERT INTO games (name, slug, installed, service, service_id) VALUES ('Berlin', 'berlin', 0, 'egs', 'map')")
c.execute("INSERT INTO games (name, slug, installed, service, service_id) VALUES ('Synced Game', 'synced-game', 0, 'egs', 'synced')")
c.executemany("INSERT INTO games (name, slug, installed, service, playtime) VALUES (?, ?, 0, 'egs', ?)",
              [("Synced Game", "synced-game", 5.0), ("Dubai", "dubai", 0),
               ("Schnellfahrstrecke Köln-Aachen", "schnellfahrstrecke-k-ln-aachen", 0)])
c.commit()
P2
run
python3 -I - "$t/.local/share/lutris/pga.db" <<'P2' || { echo "FAIL: Epic's games and add-ons (synced ones too) not as they should be"; exit 1; }
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
hidden = {i for (i,) in c.execute("SELECT game_id FROM games_categories gc JOIN categories k ON k.id = gc.category_id "
                                   "WHERE k.name = '.hidden'")}
rows = {(sid, pt, gid in hidden) for gid, sid, pt in c.execute("SELECT id, service_id, playtime FROM games WHERE service = 'egs'")}
want = {("game", 0.0, False), ("map", 0.0, True), ("synced", 5.0, False), ("route", 0.0, True), ("koln", 0.0, True)}
assert {(s, p or 0.0, h) for s, p, h in rows} == want, rows
P2
# The app menu: an installed launcher (EA App here) and game (flat-game, Steam's, from above) get Lutris's entry; Steam none (its own steam.desktop stands for
# it), nor games not installed. One you delete isn't made again; one made here goes when its game is no longer installed
apps=$t/.local/share/applications
rm -rf "$apps" "$t/.local/state/lutris-library-menu"  # (the runs above, on a library since made again)
# (EA App a Wine game in its own prefix; flat-game's icon in its Steam's cache)
mkdir -p "$t/Games/ea-app"
python3 -I - "$t/.local/share/lutris/pga.db" "$t/Games/ea-app" <<'P'
import gi, sqlite3, sys
gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0")
from lutris.config import write_game_config
config = write_game_config("ea-app", {"game": {"exe": "drive_c/EA/EALauncher.exe", "prefix": sys.argv[2]}})
c = sqlite3.connect(sys.argv[1])
c.execute("UPDATE games SET installed = 1, runner = 'wine', configpath = ? WHERE slug = 'ea-app'", (config,))
c.commit()
P
cache=${lib%/steamapps}/appcache/librarycache/42
mkdir -p "$cache" && python3 -Ic 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf; import sys; GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 32, 32).savev(sys.argv[1], "jpeg", [], [])' "$cache/$(printf 'b%.0s' {1..40}).jpg"
mkdir -p "$apps" && printf '[Desktop Entry]\nType=Application\nName=Steam\nExec=steam\n' >"$apps/steam.desktop"
run
menu() { (cd "$apps" && ls net.lutris.* 2>/dev/null | sed 's/-[0-9]*\.desktop$//' | paste -sd,); }
[[ $(menu) == net.lutris.ea-app,net.lutris.flat-game ]] || { echo "FAIL: menu entries are '$(menu)' (want EA App's and flat-game's)"; exit 1; }
grep -q '^Exec=env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/[0-9]*$' "$apps"/net.lutris.ea-app-*.desktop ||
    { echo "FAIL: EA App's menu entry doesn't start it through Lutris: $(cat "$apps"/net.lutris.ea-app-*.desktop)"; exit 1; }
# Its icon and what the dock tells its windows by (Proton: one class for all): its prefix and .exe. A Steam game: Steam's
# icon for it, the one the dock finds a steam_app_<id> window's app by
e=$(cat "$apps"/net.lutris.ea-app-*.desktop)
grep -qx 'Icon=lutris_ea-app' <<<"$e" && grep -qx "X-AgrOS-WinePrefix=$(realpath "$t/Games/ea-app")" <<<"$e" &&
    grep -qx 'X-AgrOS-WineExe=EALauncher.exe' <<<"$e" || { echo "FAIL: EA App's entry lacks its icon, prefix or .exe: $e"; exit 1; }
grep -qx 'Icon=steam_icon_42' "$apps"/net.lutris.flat-game-*.desktop && [[ -s $t/.local/share/icons/hicolor/32x32/apps/steam_icon_42.png ]] ||
    { echo "FAIL: flat-game's entry has no Steam icon: $(grep Icon "$apps"/net.lutris.flat-game-*.desktop)"; exit 1; }
rm "$apps"/net.lutris.ea-app-*.desktop
run
[[ $(menu) == net.lutris.flat-game ]] || { echo "FAIL: a menu entry you deleted was made again: $(menu)"; exit 1; }
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("UPDATE games SET installed = 1, runner = '"'wine'"' WHERE slug = '"'gog-galaxy'"'"); c.commit()' "$t/.local/share/lutris/pga.db"
run
[[ $(menu) == net.lutris.flat-game,net.lutris.gog-galaxy ]] || { echo "FAIL: a launcher installed later got no menu entry: '$(menu)'"; exit 1; }
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("UPDATE games SET installed = 0 WHERE slug = '"'gog-galaxy'"'"); c.commit()' "$t/.local/share/lutris/pga.db"
run
[[ $(menu) == net.lutris.flat-game ]] || { echo "FAIL: the menu entry of a launcher no longer installed stayed: $(menu)"; exit 1; }
# One run at a time (agros-welcome's and lutris-library.path's overlapped): another holding its lock, this one waits
flock "$XDG_RUNTIME_DIR/lutris-library.lock" sleep 3 &
sleep 0.5
start=$SECONDS; run
((SECONDS - start >= 2)) || { echo "FAIL: lutris-library ran beside another run (its lock not waited for)"; exit 1; }
wait
echo "ok lutris-library"
