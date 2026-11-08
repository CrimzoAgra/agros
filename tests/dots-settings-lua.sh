#!/usr/bin/env bash
# dots-settings' settings.lua (Hyprland's config reads it): a value with an accent written as UTF-8 outside a UTF-8 locale
# too (it failed there, settings.lua left as it was), and through a temporary file of its own run (two at once, Hyprland's
# "lua" and a "set", wrote the same one), none left behind
set -euo pipefail
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
echo "ok dots-settings-lua"
