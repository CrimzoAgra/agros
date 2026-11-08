#!/usr/bin/env bash
# lutris-library and a game on two stores: the copy that shows follows installs. The other copy hidden (by the script);
# that copy installed (Lutris keeps its id, and with it "hidden"), it shows and the first goes; it removed again, one
# copy shows, never none. A copy you hid yourself stays hidden
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t XDG_DATA_HOME=$t/.local/share XDG_CACHE_HOME=$t/.cache XDG_CONFIG_HOME=$t/.config
export DBUS_SESSION_BUS_ADDRESS=unix:path=$t/no-bus
mkdir -p "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
db=$t/.local/share/lutris/pga.db
python3 -I - <<'P'
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0")
from lutris.database.schema import syncdb
from lutris import settings
import sqlite3
syncdb()
db = sqlite3.connect(settings.DB_PATH)
with db:
    db.executemany("INSERT INTO service_games (service, appid, name, slug) VALUES (?, ?, ?, ?)",
                   [("gog", "200", "FOO", "foo"), ("steam", "100", "Foo™", "foo"),  # (the Steam copy not first)
                    ("steam", "300", "Bar", "bar"), ("egs", "400", "Bar", "bar"),
                    ("steam", "500", "!", "excl"), ("gog", "600", "?", "q")])
P
run() { python3 -I "$here/.local/bin/lutris-library" >/dev/null 2>&1 || { echo "FAIL: lutris-library failed"; python3 -I "$here/.local/bin/lutris-library"; exit 1; }; }
sql() { python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); r = c.execute(sys.argv[2]).fetchall(); c.commit(); print(",".join(str(x) for (x,) in r))' "$db" "$1"; }
shown() { sql "SELECT service FROM games WHERE service_id IN ($1) AND id NOT IN (SELECT game_id FROM games_categories gc JOIN categories c ON c.id = gc.category_id WHERE c.name = '.hidden') ORDER BY service"; }
run
[[ $(shown "'100','200'") == steam ]] || { echo "FAIL: two uninstalled copies: shown $(shown "'100','200'") (want steam)"; exit 1; }
# Names only of punctuation (no letters to compare): not copies of each other
[[ $(shown "'500','600'") == gog,steam ]] || { echo "FAIL: games named only punctuation taken as copies: shown '$(shown "'500','600'")'"; exit 1; }
# The GOG copy installed (from the Hidden view or the GOG page: the same row, its id kept)
sql "UPDATE games SET installed = 1, runner = 'wine' WHERE service = 'gog'" >/dev/null
run
[[ $(shown "'100','200'") == gog ]] || { echo "FAIL: the hidden copy installed: shown '$(shown "'100','200'")' (want gog, the installed one)"; exit 1; }
# Removed again: one copy shows
sql "UPDATE games SET installed = 0 WHERE service = 'gog'" >/dev/null
run
[[ $(shown "'100','200'") =~ ^(steam|gog)$ ]] || { echo "FAIL: the installed copy removed: shown '$(shown "'100','200'")' (want one copy)"; exit 1; }
# A copy the script hid that you unhid in Lutris: stays shown (the script doesn't hide it again)
sql "DELETE FROM games_categories WHERE game_id IN (SELECT id FROM games WHERE service_id IN ('100','200'))" >/dev/null
run
[[ $(shown "'100','200'") == gog,steam ]] || { echo "FAIL: a copy you unhid was hidden again: shown '$(shown "'100','200'")'"; exit 1; }
# Hidden by you (not by the script): stays hidden even when installed
sql "INSERT INTO games_categories (game_id, category_id) SELECT g.id, c.id FROM games g, categories c WHERE g.service = 'steam' AND g.service_id = '300' AND c.name = '.hidden'" >/dev/null
sql "UPDATE games SET installed = 1, runner = 'wine' WHERE service = 'steam' AND service_id = '300'" >/dev/null
run
[[ $(shown "'300','400'") == "" ]] || { echo "FAIL: a copy you hid was shown again, or the other kept: shown '$(shown "'300','400'")'"; exit 1; }
echo "ok lutris-library-copies"
