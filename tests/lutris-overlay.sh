#!/usr/bin/env bash
# The Lutris launcher in a throwaway home: the overlay applies to the installed Lutris, launches at once share one
# build, and the patched copy is what runs (lutris --version: no window)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[[ -x /usr/bin/lutris ]] || { echo "skip lutris-overlay (Lutris not installed)"; exit 0; }
mkdir -p "$t/.local/share" "$t/bin"
# Your Settings app choices don't reach the test: every change on, unless one is named. The launcher's stamp reads them
# from ~/.config/dots/settings.json, the patch from dots-settings: both from the same file here
settings() { mkdir -p "$t/.config/dots"; if (($#)); then echo "{\"lutris.$1\": false}"; else echo "{}"; fi >"$t/.config/dots/settings.json"; }
settings
printf '#!/bin/sh\ncat %s/.config/dots/settings.json\n' "$t" >"$t/bin/dots-settings"; chmod +x "$t/bin/dots-settings"
cp -r "$here/.local/share/lutris-overlay" "$t/.local/share/"
printf '#!/bin/sh\necho "$*" >>%s/notified\n' "$t" >"$t/bin/notify-send"; chmod +x "$t/bin/notify-send"
run() { HOME=$t XDG_CACHE_HOME=$t/cache PATH=$t/bin:$PATH DOTS_SETTINGS=$t/bin/dots-settings "$here/.local/bin/lutris" --version 2>&1; }

for _ in 1 2 3; do run >/dev/null & done; wait
[[ ! -e $t/notified ]] || fail "a launch reported the overlay off: $(cat "$t/notified")"

# Battle.net (bnet_login): the account site's names to Lutris's games; a game that left Battle.net, an unknown one: none
bnet_check() {
HOME=$t XDG_CACHE_HOME=$t/cache python3 -I - "$t/cache/lutris-overlay" "$t" <<'P' || fail "Battle.net names matched wrong"
import json, os, sys
sys.path.insert(0, sys.argv[1])
os.makedirs(sys.argv[2] + "/cache/lutris", exist_ok=True)
import lutris.gui.application  # noqa: F401 (Gtk versions, as Lutris loads them)
from lutris.services import battlenet as bn
s = bn.BattleNetService.__new__(bn.BattleNetService)
s.owned_path = sys.argv[2] + "/owned.json"
json.dump(["Overwatch®", "World of Warcraft®", "Diablo® III", "Hearthstone®", "Destiny 2", "Some New Game"],
          open(s.owned_path, "w"))
os.utime(s.owned_path, (0, 0))
s._refresh = lambda: None  # no network: the kept list
saved = []
bn.BattleNetGame.save = lambda self: saved.append(self.appid)
s.load()
want = ["d3", "hsb", "pro", "wow", "wow_classic", "wow_classic_era"]
assert sorted(saved) == want, sorted(saved)
P
}
bnet_check

# revive_installed: a store game uninstalled in Lutris, then found installed again by its store's scan (Epic here):
# its old entry is installed again (same id, so its playtime stays), not left "not installed"
HOME=$t XDG_CACHE_HOME=$t/cache XDG_DATA_HOME=$t/.local/share XDG_CONFIG_HOME=$t/.config python3 -I - "$t/cache/lutris-overlay" <<'P2' || fail "an uninstalled Epic game found again isn't installed again"
import sys
sys.path.insert(0, sys.argv[1])
import lutris.gui.application  # noqa: F401
from lutris import settings
from lutris.database import sql
from lutris.database.schema import syncdb
from lutris.startup import init_dirs
from lutris.database.games import add_game, get_game_by_field
from lutris.services.egs import EpicGamesStoreService
init_dirs(); syncdb()
sql.db_insert(settings.DB_PATH, "service_games", {"service": "egs", "appid": "Fortnite", "name": "Fortnite", "slug": "fortnite"})
launcher = {"configpath": "egs-launcher", "runner": "wine", "directory": "/prefix"}
old = add_game(name="Fortnite", slug="fortnite", installed=0, runner="", installer_slug="fortnite-egs", playtime=5.0,
               service="egs", service_id="Fortnite")
EpicGamesStoreService().install_from_egs(launcher, {"AppName": "Fortnite"})
games = sql.db_select(settings.DB_PATH, "games", condition=("service", "egs"))
assert len(games) == 1 and games[0]["id"] == old, games
g = get_game_by_field(old, "id")
assert g["installed"] == 1 and g["runner"] == "wine" and g["playtime"] == 5.0 and g["configpath"], g
P2
[[ -f $t/cache/lutris-overlay/stamp && ! -e $t/cache/lutris-overlay.failed ]] || fail "no build"
[[ -z $(compgen -G "$t/cache/lutris-overlay.new.*") ]] || fail "temp builds left"
for f in "$t"/cache/lutris-overlay/lutris/gui/widgets/cellrenderers.py "$t"/cache/lutris-overlay/lutris/gui/lutriswindow.py; do
    [[ ! -L $f ]] || fail "${f##*/} not patched"
    python3 -m py_compile "$f" || fail "${f##*/} doesn't compile"
done
run | grep -qi lutris || fail "the patched copy doesn't start"
# Not rebuilt while the patched Lutris runs (its folder swapped under it): only once it has closed
before=$(cat "$t/cache/lutris-overlay/stamp")
(exec -a "python3 $t/cache/lutris-overlay/bin/lutris" sleep 30) & fake=$!
settings rounded_covers
run >/dev/null
[[ $(cat "$t/cache/lutris-overlay/stamp") == "$before" ]] || fail "rebuilt under the running Lutris"
kill "$fake"; wait "$fake" 2>/dev/null || true
run >/dev/null
[[ $(cat "$t/cache/lutris-overlay/stamp") != "$before" ]] || fail "not rebuilt once Lutris had closed"
settings; run >/dev/null
grep -q '"library-refresh"' "$t/cache/lutris-overlay/lutris/gui/application.py" || fail "the library-refresh action isn't in the build"
HOME=$t python3 -I - "$t/cache/lutris-overlay" "$t" <<'P' || fail "the patched Lutris doesn't find Flathub's Steam in .local/share/Steam"
import os, sys
sys.path.insert(0, sys.argv[1])
os.makedirs(sys.argv[2] + "/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps")
from lutris.util.steam.config import get_steamapps_dirs
assert any(d.endswith("/.local/share/Steam/steamapps") for d in get_steamapps_dirs()), list(get_steamapps_dirs())
P
# The Rockstar source (rockstar_source): registered, on by default; the account's games (gamesOwned, as a list or one
# string) to Lutris's, none before signing in
rockstar_check() {
HOME=$t XDG_CACHE_HOME=$t/cache python3 -I - "$t/cache/lutris-overlay" <<'P' || fail "the Rockstar source isn't right in the patched Lutris"
import json, os, sys
sys.path.insert(0, sys.argv[1])
import lutris.gui.application  # noqa: F401 (Gtk versions, as Lutris loads them)
from lutris.services import DEFAULT_SERVICES, SERVICES
from lutris.services import signin
from lutris.services.rockstar import RockstarGame
assert "rockstar" in SERVICES and "rockstar" in DEFAULT_SERVICES
s = SERVICES["rockstar"]()
os.makedirs(os.path.dirname(s.owned_path), exist_ok=True)
if os.path.exists(s.owned_path):
    os.remove(s.owned_path)  # (a run before)
saved = []
RockstarGame.save = lambda self: saved.append(self.appid)
assert s.load() == [] and not saved  # not signed in: nothing
assert s.owned_names({"x": {"gamesOwned": "GTAV|RDR2"}}) == ["GTAV", "RDR2"]
assert s.owned_names({"gamesOwned": ["Max Payne 3", {"name": "L.A. Noire"}]}) == ["Max Payne 3", "L.A. Noire"]
assert s.owned_names({"memberId": 1}) is None
json.dump(["GTAV", "Red Dead Redemption 2", "gta trilogy", "Some New Game"], open(s.owned_path, "w"))
s.load()
assert sorted(saved) == ["gta3de", "gta5", "gtasade", "gtavcde", "rdr2"], saved
# A reload that read the list again: saved whole (a temp file renamed over the old one), then listed
os.utime(s.owned_path, (0, 0))
s._refresh = lambda: ["Max Payne 3"]
replaced, real = [], os.replace
signin.os.replace = lambda a, b: replaced.append((a, b)) or real(a, b)
saved.clear()
s.load()
assert replaced == [(s.owned_path + ".tmp", s.owned_path)] and not os.path.exists(s.owned_path + ".tmp"), replaced
assert json.load(open(s.owned_path)) == ["Max Payne 3"] and saved == ["mp3"], saved
# Odd data never raises: an id that's a number, a kept list with null and numbers in it; handed-over data that isn't
# JSON ends the sign-in (no window left on the hand-over page, no unseen reload waiting 45 s)
assert s.owned_names({"gamesOwned": [{"id": 5}, "GTAV"]}) == ["5", "GTAV"]
json.dump([None, 5, "GTAV"], open(s.owned_path, "w"))
saved.clear()
s.load()
assert saved == ["gta5"], saved
class View:
    handlers = {}
    def connect(self, signal, handler): self.handlers[signal] = handler
class Request:
    def get_uri(self): return s.hand_over + "d=%7Bnot-json"
ended = []
s._watch(View(), ended.append)
View.handlers["resource-load-started"](None, None, Request())
assert ended == [None], ended
P
}
rockstar_check
# The sidebar: Launchers a Library row, the sources' icons drawn like the covers' (store_icons)
grep -q '"Launchers",' "$t/cache/lutris-overlay/lutris/gui/widgets/sidebar.py" || fail "Launchers isn't a Library row"
grep -q '_store_icon(service) or' "$t/cache/lutris-overlay/lutris/gui/widgets/sidebar.py" || fail "the sidebar's source icons aren't the covers'"
grep -q 'def on_sync_all_clicked' "$t/cache/lutris-overlay/lutris/gui/lutriswindow.py" || fail "no sync-all button in the header"
grep -q "size = (176, 264)" "$t/cache/lutris-overlay/lutris/services/base.py" || fail "covers aren't 2:3 (tall_covers)"
grep -q "size = (176, 264)" "$t/cache/lutris-overlay/lutris/services/rockstar.py" || fail "Rockstar covers aren't 2:3 (tall_covers)"
cp "$t/.local/share/lutris-overlay/patch.py" "$t/patch.orig" && cp "$t/.local/share/lutris-overlay/sections.py" "$t/sections.orig"

# A change switched off in the Settings app stays out of the build (a rebuild, not a warning); back on, it's back
settings launchers_apart
run >/dev/null
[[ ! -e $t/notified ]] || fail "a change switched off was reported: $(cat "$t/notified")"
grep -q launchers_apart "$t/cache/lutris-overlay/lutris/gui/lutriswindow.py" && fail "a change switched off (launchers_apart) is still in the build"
settings
run >/dev/null
grep -q launchers_apart "$t/cache/lutris-overlay/lutris/gui/lutriswindow.py" || fail "a change switched back on isn't back in the build"

# Battle.net's sign-in and Rockstar share signin.py: each works with the other switched off
build=$t/cache/lutris-overlay/lutris
settings rockstar_source
run >/dev/null
[[ ! -e $build/services/rockstar.py && -f $build/services/signin.py ]] || fail "rockstar_source off: rockstar.py in the build, or signin.py not"
run | grep -qi lutris || fail "the build without rockstar_source doesn't start"
bnet_check
settings bnet_login
run >/dev/null
grep -q lutris-owned "$build/services/battlenet.py" && fail "bnet_login switched off is still in the build"
[[ -f $build/services/signin.py ]] || fail "bnet_login off: signin.py not in the build (Rockstar needs it)"
run | grep -qi lutris || fail "the build without bnet_login doesn't start"
rockstar_check
settings
run >/dev/null

# An optional change that no longer fits: left out (its file not half-patched), the rest still on, and said so
sed -i 's/^def rounded_covers():/def rounded_covers():\n    edit("gui\/widgets\/cellrenderers.py", "class ", "class ")\n    raise Miss("cover anchor gone")/' \
    "$t/.local/share/lutris-overlay/patch.py"
run >/dev/null
[[ $(cat "$t/cache/lutris-overlay/stamp" 2>/dev/null) && ! -e $t/cache/lutris-overlay.failed ]] || fail "an optional miss failed the build"
grep -q "some of your changes are off Covers with rounded corners" "$t/notified" || fail "an optional miss wasn't reported: $(cat "$t/notified")"
[[ -L $t/cache/lutris-overlay/lutris/gui/lutriswindow.py ]] && fail "an optional miss turned the other changes off"
run | grep -qi lutris || fail "the build without one change doesn't start"
rm -f "$t/notified"; cp "$t/patch.orig" "$t/.local/share/lutris-overlay/patch.py"

# Patched but no longer loading (it uses something an update renamed): plain Lutris, said so
echo 'import lutris.renamed_in_an_update' >>"$t/.local/share/lutris-overlay/sections.py"
run >/dev/null || true
grep -q "renamed_in_an_update" "$t/notified" || fail "a patched Lutris that doesn't load wasn't reported: $(cat "$t/notified" 2>&1)"
[[ -e $t/cache/lutris-overlay.failed ]] || fail "a patched Lutris that doesn't load was kept"
rm -f "$t/notified"; cp "$t/sections.orig" "$t/.local/share/lutris-overlay/sections.py"

# The start-up checks' call renamed in an update (startup_once's end): the build fails, the rest of the file not taken
# into the once-only block
src=$(python3 -Ic 'import sysconfig; print(sysconfig.get_path("purelib"))')/lutris
cp -r "$src" "$t/src" && sed -i '/^        run_all_checks(/d' "$t/src/gui/application.py"
mkdir "$t/root" && cp -as "$t/src" "$t/root/lutris"
out=$(DOTS_SETTINGS=$t/bin/dots-settings python3 -I "$t/.local/share/lutris-overlay/patch.py" "$t/src" "$t/root" 2>&1) &&
    fail "a start-up block with no run_all_checks was patched"
[[ $out == *"start-up block not found"* ]] || fail "a missing run_all_checks wasn't the reason: $out"

# A change that no longer fits (after an update): plain Lutris starts, not the old build
echo 'raise SystemExit("anchor gone")' >>"$t/.local/share/lutris-overlay/patch.py"
printf '#!/bin/sh\necho "$0 $*" >>%s/started\n' "$t" >"$t/fake"; chmod +x "$t/fake"
cp "$t/fake" "$t/cache/lutris-overlay/bin/lutris"   # the old build, if it were started
run >/dev/null || true
[[ ! -e $t/started ]] || fail "the old build started after a failed rebuild"
grep -q "anchor gone" "$t/notified" || fail "the failure wasn't reported"
# (after the rebuilds above: the build each swapped out, and the failed one, taken away)
[[ -z $(compgen -G "$t/cache/lutris-overlay.new.*") ]] || fail "temp builds left after rebuilds"
# Lutris's icons half fetched (its first start offline): they and the runtime list go, so Lutris fetches them again;
# whole, both kept
icons=$t/.local/share/lutris/runtime/icons/hicolor/scalable/apps; mkdir -p "$icons" "$t/cache/lutris"
touch "$icons/wine.svg" "$t/cache/lutris/versions.json"
run >/dev/null
[[ ! -e ${icons%%/hicolor*} && ! -e $t/cache/lutris/versions.json ]] || fail "half-fetched icons kept"
mkdir -p "$icons"; touch "$icons/steam.svg" "$t/cache/lutris/versions.json"
run >/dev/null
[[ -e $icons/steam.svg && -e $t/cache/lutris/versions.json ]] || fail "whole icons taken away"

# ...and on Lutris's main (the next release: a change there that breaks one shows here first, as Caelestia's main does in
# caelestia-overlay); an optional one left out only warns, any other one failing fails here
if timeout 120 git clone -q --depth 1 https://github.com/lutris/lutris "$t/lutris-main" 2>/dev/null; then
    mkdir -p "$t/main-root" && cp -as "$t/lutris-main/lutris" "$t/main-root/lutris"
    out=$(DOTS_SETTINGS=/bin/false python3 -I "$here/.local/share/lutris-overlay/patch.py" "$t/lutris-main/lutris" "$t/main-root" 2>&1) ||
        fail "the overlay doesn't build on Lutris's main: $out"
    n=$(grep -c WARNING <<<"$out" || true)
    echo "ok lutris-overlay (on Lutris main: $n optional changes left out)"
else
    echo "ok lutris-overlay (SKIPPED: Lutris's main: offline)"
fi
