#!/usr/bin/env bash
# epic-tray's menu: the Epic games installed in Lutris's library (by name; not installed ones, nor other stores'), then
# Epic's pages and Exit; with none installed, no separator above the pages
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/data/lutris"
python3 -I - "$t/data/lutris/pga.db" <<'P'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, service TEXT, installed INTEGER)")
c.executemany("INSERT INTO games (id, name, service, installed) VALUES (?, ?, ?, ?)",
              [(40, "Zeta", "egs", 1), (41, "alpha", "egs", 1), (42, "Gone", "egs", 0), (43, "Steamy", "steam", 1)])
c.commit()
P
menu=$(XDG_DATA_HOME=$t/data python3 -I "$here/.local/bin/epic-tray" --menu)
labels=$(python3 -Ic 'import json, sys; print("|".join(str(e["label"]) for e in json.loads(sys.argv[1])))' "$menu")
[[ $labels == "alpha|Zeta|None|Library|Store|Unreal Engine|None|Exit" ]] || fail "menu: $labels"
rm "$t/data/lutris/pga.db"
menu=$(XDG_DATA_HOME=$t/data python3 -I "$here/.local/bin/epic-tray" --menu)
labels=$(python3 -Ic 'import json, sys; print("|".join(str(e["label"]) for e in json.loads(sys.argv[1])))' "$menu")
[[ $labels == "Library|Store|Unreal Engine|None|Exit" ]] || fail "menu with no library: $labels"
echo "ok epic-tray"
