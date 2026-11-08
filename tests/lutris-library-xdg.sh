#!/usr/bin/env bash
# lutris-library with XDG_CACHE_HOME set: the patched Lutris (~/.local/bin/lutris builds it there) is found, so a
# Battle.net sign-in counts and the account's games join
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t XDG_DATA_HOME=$t/.local/share XDG_CACHE_HOME=$t/xdg-cache XDG_CONFIG_HOME=$t/.config
export DBUS_SESSION_BUS_ADDRESS=unix:path=$t/no-bus
mkdir -p "$t/.local/share/lutris" "$t/xdg-cache/lutris" "$t/.config/lutris" "$t/xdg-cache/lutris-overlay/lutris/services"
echo '# lutris-owned' >"$t/xdg-cache/lutris-overlay/lutris/services/battlenet.py"
echo '["StarCraft II"]' >"$t/xdg-cache/lutris/bnet-owned.json"
python3 -I - <<'P'
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0")
from lutris.database.schema import syncdb
from lutris import settings
import sqlite3
syncdb()
db = sqlite3.connect(settings.DB_PATH)
with db:
    db.execute("INSERT INTO service_games (service, appid, name, slug) VALUES ('battlenet', 's2', 'StarCraft II', 'starcraft-ii')")
P
python3 -I "$here/.local/bin/lutris-library" >/dev/null 2>&1 || { echo "FAIL: lutris-library failed"; exit 1; }
got=$(python3 -Ic 'import sqlite3, sys; print(",".join(r[0] for r in sqlite3.connect(sys.argv[1]).execute("SELECT service_id FROM games WHERE service = ?", ("battlenet",))))' "$t/.local/share/lutris/pga.db")
[[ $got == s2 ]] || { echo "FAIL: signed in with XDG_CACHE_HOME set, Battle.net games are '$got' (want s2)"; exit 1; }
echo "ok lutris-library-xdg"
