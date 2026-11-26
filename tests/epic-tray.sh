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
# Epic's processes: yours, not another account's logged in beside yours (its Epic kept your icon after yours quit)
out=$(python3 -I - "$here/.local/bin/epic-tray" 2>&1 <<'P'
import importlib.machinery, importlib.util, io, os, sys
loader = importlib.machinery.SourceFileLoader("et", sys.argv[1])
et = importlib.util.module_from_spec(importlib.util.spec_from_loader("et", loader))
loader.exec_module(et)
def owner(d):
    try:
        return os.stat(f"/proc/{d}").st_uid
    except OSError:
        return os.getuid()
other = next((d for d in filter(str.isdigit, os.listdir("/proc")) if owner(d) != os.getuid()), None)
if other is None:
    print("skip: no other account's process here")
    sys.exit(0)
epic = {other: b"/usr/bin/python3\0/usr/bin/umu-run\0C:\\Epic\\EpicGamesLauncher.exe\0",
        str(os.getpid()): b"C:\\Epic\\EpicGamesLauncher.exe\0"}
real = open
et.open = lambda path, *a, **k: io.BytesIO(epic[path.split("/")[2]]) \
    if path.endswith("/cmdline") and path.split("/")[2] in epic else real(path, *a, **k)
got = et.epic()
print("ok" if got == (None, [os.getpid()]) else f"Epic's processes: {got} (want only yours: {os.getpid()})")
P
)
case $out in
    ok) ;;
    skip:*) skipped "${out#skip: }" ;;
    *) fail "$out" ;;
esac
echo "ok epic-tray"
