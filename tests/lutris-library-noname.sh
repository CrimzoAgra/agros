#!/usr/bin/env bash
# lutris-library and a Steam manifest with no "name" yet (Steam rewriting it mid-download): skipped, the run carries
# on; saved, its NULL name crashed this run and every later one
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t XDG_DATA_HOME=$t/.local/share XDG_CACHE_HOME=$t/.cache XDG_CONFIG_HOME=$t/.config
export DBUS_SESSION_BUS_ADDRESS=unix:path=$t/no-bus
mkdir -p "$t/.local/share/Steam/steamapps/common/G" "$t/.local/share/Steam/appcache" "$t/.local/share/lutris" "$t/.cache/lutris" "$t/.config/lutris"
cat >"$t/.local/share/Steam/steamapps/libraryfolders.vdf" <<V
"libraryfolders"
{
	"0"
	{
		"path"		"$t/.local/share/Steam"
		"apps" { "4242" "1" }
	}
}
V
cat >"$t/.local/share/Steam/steamapps/appmanifest_4242.acf" <<'A'
"AppState"
{
	"appid"		"4242"
	"StateFlags"		"4"
	"installdir"		"G"
}
A
out=$(timeout 120 python3 -I "$here/.local/bin/lutris-library" 2>&1) || fail "a manifest with no name crashed it: $(tail -3 <<<"$out")"
rows=$(python3 -Ic "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('SELECT count(*) FROM games WHERE name IS NULL').fetchone()[0])" "$t/.local/share/lutris/pga.db")
[[ $rows == 0 ]] || fail "a game with no name was saved ($rows)"
echo "ok lutris-library-noname"
