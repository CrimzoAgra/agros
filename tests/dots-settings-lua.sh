#!/usr/bin/env bash
# dots-settings' settings.lua (Hyprland's config reads it): a value with an accent written as UTF-8 outside a UTF-8 locale
# too (it failed there, settings.lua left as it was), and through a temporary file of its own run (two at once, Hyprland's
# "lua" and a "set", wrote the same one), none left behind; and under the settings' lock, as a set is
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 python3 - "$here" "$t" <<'P' || fail "settings.lua not written outside a UTF-8 locale"
import importlib.machinery, importlib.util, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.CONFIG, ds.SETTINGS = f"{t}/dots", f"{t}/dots/settings.json"
ds.write_lua({"place.name": {"key": "place.name", "type": "string", "default": "Olá"}})
P
grep -qx '    \["place.name"\] = "Olá",' "$t/dots/settings.lua" || fail "the value not in settings.lua: $(cat "$t/dots/settings.lua")"
[[ -z $(find "$t/dots" -name '*.tmp') ]] || fail "a temporary file left: $(ls "$t/dots")"
# "lua" (Hyprland's config runs it) under the settings' lock, as a "set" is: it read settings.json before a set wrote it
# and put its older settings.lua over the set's
python3 -I - "$here" "$t" <<'P' || fail "dots-settings lua didn't wait for a set holding the settings' lock"
import fcntl, importlib.machinery, importlib.util, os, sys, threading, time
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.CONFIG, ds.SETTINGS = f"{t}/lock", f"{t}/lock/settings.json"
ds.SCHEMA, ds.AUTOSTART, ds.PATCHES = f"{here}/.local/share/dots-settings/schema.json", [], {}
os.makedirs(ds.CONFIG)
held = open(f"{ds.CONFIG}/.settings.lock", "w")
fcntl.flock(held, fcntl.LOCK_EX)
run = threading.Thread(target=ds.main, args=(["lua"],))
run.start()
time.sleep(1)
assert not os.path.exists(f"{ds.CONFIG}/settings.lua"), "written while a set held the lock"
held.close()
run.join(10)
assert os.path.exists(f"{ds.CONFIG}/settings.lua"), "not written once the lock was let go of"
P
echo "ok dots-settings-lua"
