#!/usr/bin/env bash
# lutris-library and an open Lutris (a stand-in with the library-refresh action, on a session bus of the test's own):
# told to refresh when the run changed the library, not when it changed nothing (lutris-library.path starts it on every
# read Lutris makes: a refresh each time reset the view, and its reads started the next run)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
command -v dbus-run-session >/dev/null || { echo "skip lutris-library-refresh (no dbus-run-session)"; exit 0; }
export HOME=$t XDG_DATA_HOME=$t/.local/share XDG_CACHE_HOME=$t/.cache XDG_CONFIG_HOME=$t/.config T=$t HERE=$here
mkdir -p "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
cat >"$t/lutris.py" <<'P'
import sys
from gi.repository import Gio
app = Gio.Application(application_id="net.lutris.Lutris")
action = Gio.SimpleAction.new("library-refresh", None)
action.connect("activate", lambda *_: open(sys.argv[1] + "/refreshed", "a").write("x\n"))
app.add_action(action)
app.connect("activate", lambda *_: open(sys.argv[1] + "/ready", "w").close())
app.hold()
app.run([])
P
cat >"$t/test" <<'S'
set -euo pipefail
python3 -I "$T/lutris.py" "$T" & trap "kill $!" EXIT
for _ in $(seq 100); do [[ -e $T/ready ]] && break; sleep 0.1; done
[[ -e $T/ready ]] || { echo "FAIL: the stand-in Lutris did not start"; exit 1; }
refreshes() { cat "$T/refreshed" 2>/dev/null | wc -l; }
fail() { echo "FAIL: $1 ($(tr '\n' ';' <<<"$out"))"; exit 1; }
run() { out=$(python3 -I "$HERE/.local/bin/lutris-library" 2>&1) || fail "lutris-library failed"; }
run   # a new database: the launchers listed
[[ $(refreshes) == 1 ]] || fail "the run that listed the launchers refreshed Lutris $(refreshes) times (want 1)"
run   # nothing new
[[ $(refreshes) == 1 ]] || fail "a run that changed nothing refreshed Lutris"
python3 -Ic 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("INSERT INTO service_games (service, appid, name, slug) VALUES (?, ?, ?, ?)", ("gog", "1", "Game", "game")); c.commit()' \
    "$T/.local/share/lutris/pga.db"
run   # a store game added
[[ $(refreshes) == 2 ]] || fail "a run that added a game did not refresh Lutris"
echo "ok lutris-library-refresh"
S
dbus-run-session -- bash "$t/test"
