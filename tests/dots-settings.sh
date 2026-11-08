#!/usr/bin/env bash
# dots-settings' settings.lua, loaded by real Lua: every setting comes through with its type, non-ASCII and quotes
# included (a file Lua can't read turns every shortcut off)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip dots-settings (no lua)"; exit 0; }
python3 -I - "$here" "$t" <<'P'
import importlib.machinery, importlib.util, json, subprocess, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.SCHEMA, ds.CONFIG, ds.SETTINGS = f"{here}/.local/share/dots-settings/schema.json", t, f"{t}/settings.json"
ds.PATCHES = {"caelestia": f"{here}/.local/share/caelestia-overlay/patch.py", "lutris": f"{here}/.local/share/lutris-overlay/patch.py"}
settings = ds.all_settings(ds.schema())
key = next(k for k, s in settings.items() if k.startswith("keys.") and "get" not in s)
saved = {key: ["SUPER + ç", 'ALT + "x"']}
json.dump(saved, open(ds.SETTINGS, "w"))
ds.write_lua(settings)
dump = 'for k, v in pairs(dofile(arg[1])) do io.write(k, "\\t", type(v) == "table" and table.concat(v, "|") or tostring(v), "\\n") end'
out = subprocess.run(["lua", "-e", dump.replace("arg[1]", repr(f"{t}/settings.lua"))], capture_output=True, text=True)
assert out.returncode == 0, f"Lua can't load settings.lua: {out.stderr}"
got = dict(line.split("\t", 1) for line in out.stdout.splitlines())
assert got[key] == 'SUPER + ç|ALT + "x"', got[key]
# Caelestia's shortcuts only once changed: written with their defaults, a Caelestia update's new ones never reached them
assert not [k for k in got if k.startswith("caelestia-keys.")], [k for k in got if k.startswith("caelestia-keys.")]
for k, s in settings.items():
    if "get" in s or "autostart" in s or s["type"] == "keys":
        continue
    want = s["default"]
    shown = got.get(k, "nil")
    assert shown == (str(want).lower() if isinstance(want, bool) else str(want)), (k, shown, want)
P
echo "ok dots-settings"
