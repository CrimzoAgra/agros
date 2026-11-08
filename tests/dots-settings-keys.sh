#!/usr/bin/env bash
# Out of the box no two shortcuts share keys (my keys.* defaults against Caelestia's own, after hypr-vars.lua's
# changes): Hyprland runs every bind on the keys, so pressing one does both (Capri's Ctrl+Alt+C also cleared every
# notification). Against the Caelestia installed here, as the Settings app shows a clash
set -euo pipefail
. "$(dirname "$0")/lib.sh"
vars=$HOME/.config/hypr/variables.lua
[[ -f $vars ]] || { echo "skip dots-settings-keys (no Caelestia)"; exit 0; }
mkdir -p "$t/.config/hypr"
cp -r "$here/.config/caelestia" "$t/.config/"
cp "$vars" "$t/.config/hypr/"
python3 -I - "$here" "$t" <<'P'
import importlib.machinery, importlib.util, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.HOME, ds.SCHEMA, ds.AUTOSTART = t, f"{here}/.local/share/dots-settings/schema.json", []
ds.PATCHES = {"caelestia": f"{here}/.local/share/caelestia-overlay/patch.py", "lutris": f"{here}/.local/share/lutris-overlay/patch.py"}
settings = ds.all_settings(ds.schema())
assert any(k.startswith("caelestia-keys.") for k in settings), "Caelestia's shortcuts not read"
# One hypr-vars.lua moves (not turns off) is still offered, with its keys: compared below, and can be changed
assert settings["caelestia-keys.kbClearNotifs"]["default"] == ["CTRL + ALT + C"], "kbClearNotifs not offered"
assert "caelestia-keys.kbMusicWs" not in settings, "a shortcut turned off is offered"


def norm(keys):  # as the Settings app compares them
    parts = [p.strip().lower() for p in keys.split("+")]
    return "+".join(sorted(parts[:-1]) + parts[-1:])


used = {}
for k, s in settings.items():
    if s["type"] != "keys":
        continue
    for keys in s["default"]:
        for one in ([f"{keys} + {d}" for d in "1234567890"] if s.get("modifier") else [keys]):
            used.setdefault(norm(one), []).append(k)
clashes = {keys: ks for keys, ks in used.items() if len(ks) > 1}
assert not clashes, clashes
P
echo "ok dots-settings-keys"
