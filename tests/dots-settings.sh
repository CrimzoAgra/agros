#!/usr/bin/env bash
# dots-settings' settings.lua, loaded by real Lua: every setting comes through with its type, non-ASCII, quotes and
# control characters included (in names too: a screen's description) (a file Lua can't read turns every shortcut off)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
command -v lua >/dev/null || { echo "skip dots-settings (no lua)"; exit 0; }
python3 -I - "$here" "$t" <<'P'
import importlib.machinery, importlib.util, json, subprocess, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.CACHE, ds.CAELESTIA_DIR = f"{t}/caelestia-options.json", f"{t}/caelestia"  # (not your home's)
ds.OPTIONS_QML = f"{here}/.local/share/dots-settings/caelestia-options.qml"  # (the repo's, not your home's)
ds.SCHEMA, ds.CONFIG, ds.SETTINGS = f"{here}/.local/share/dots-settings/schema.json", t, f"{t}/settings.json"
ds.PATCHES = {"caelestia": f"{here}/.local/share/caelestia-overlay/patch.py", "lutris": f"{here}/.local/share/lutris-overlay/patch.py"}
settings = ds.all_settings(ds.schema())
key = next(k for k, s in settings.items() if k.startswith("keys.") and "get" not in s)
# A screen's description (its name in the key) with non-ASCII and a control character before a digit, a value with \
screen = "screens.Büro\x011 \\ Bildschirm\x7f.position"
saved = {key: ["SUPER + ç", 'ALT + "x"'], screen: "Bü\x07\x1f0x0"}
json.dump(saved, open(ds.SETTINGS, "w"))
ds.write_lua(settings)
dump = 'for k, v in pairs(dofile(arg[1])) do io.write(k, "\\t", type(v) == "table" and table.concat(v, "|") or tostring(v), "\\n") end'
out = subprocess.run(["lua", "-e", dump.replace("arg[1]", repr(f"{t}/settings.lua"))], capture_output=True, text=True)
assert out.returncode == 0, f"Lua can't load settings.lua: {out.stderr}"
got = dict(line.split("\t", 1) for line in out.stdout.splitlines())
assert got[key] == 'SUPER + ç|ALT + "x"', got[key]
open(f"{t}/check.lua", "w").write('local s = dofile(arg[1]); assert(s[arg[2]] == arg[3], tostring(s[arg[2]]))')
out = subprocess.run(["lua", f"{t}/check.lua", f"{t}/settings.lua", screen, saved[screen]], capture_output=True, text=True)
assert out.returncode == 0, f"a screen's non-ASCII or control-character name or value read back wrong: {out.stderr}"
assert subprocess.run(["luac", "-p", f"{t}/settings.lua"]).returncode == 0, "luac -p refuses settings.lua"
# Caelestia's shortcuts only once changed: written with their defaults, a Caelestia update's new ones never reached them
assert not [k for k in got if k.startswith("caelestia-keys.")], [k for k in got if k.startswith("caelestia-keys.")]
for k, s in settings.items():
    # (Caelestia's options are in its own files; its variables and the screens' only once changed)
    if {"get", "autostart", "path", "readonly"} & s.keys() or s["type"] == "keys" or k.startswith(("caelestia-vars.", "screens.")):
        continue
    want = s["default"]
    shown = got.get(k, "nil")
    assert shown == (str(want).lower() if isinstance(want, bool) else str(want)), (k, shown, want)
P
echo "ok dots-settings"
