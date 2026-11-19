#!/usr/bin/env bash
# Out of the box no two shortcuts share keys (my keys.* defaults against Caelestia's own, after hypr-vars.lua's
# changes): Hyprland runs every bind on the keys, so pressing one does both (Capri's Ctrl+Alt+C also cleared every
# notification), nor with Capri's fixed keys; and every key the manual's shortcuts page lists is one of them. Against the
# Caelestia installed here, as the Settings app shows a clash
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
ds.CACHE, ds.CAELESTIA_DIR = f"{t}/caelestia-options.json", f"{t}/caelestia"  # (not your home's)
ds.OPTIONS_QML = f"{here}/.local/share/dots-settings/caelestia-options.qml"  # (the repo's, not your home's)
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
    if s["type"] != "keys" or s.get("reserved"):  # (Capri's own: below)
        continue
    for keys in s["default"]:
        for one in ([f"{keys} + {d}" for d in "1234567890"] if s.get("modifier") else [keys]):
            used.setdefault(norm(one), []).append(k)
clashes = {keys: ks for keys, ks in used.items() if len(ks) > 1}
assert not clashes, clashes
# Nor any of them with Capri's fixed keys: she binds those herself while she runs (her hotkeys.rs, RESERVED: talk,
# always listening, chat, the scanner), and her Ctrl+Alt+V, Ctrl+Alt+Shift+V and Ctrl+Alt+C once did Caelestia's sound
# settings, its paste of the latest clip and its clear-notifications along with her own
capri = {norm(k): k for k in ("CTRL + ALT + Space", "CTRL + ALT + SHIFT + Space", "CTRL + ALT + K", "CTRL + ALT + X")}
taken = {capri[keys]: ks for keys, ks in used.items() if keys in capri}
assert not taken, f"Capri's fixed keys taken: {taken}"
# And they're the ones the Shortcuts page shows as hers (refused for any other shortcut)
shown = {norm(k) for s in settings.values() if s.get("reserved") == "Capri's" for k in s["default"]}
assert shown == set(capri), f"the Shortcuts page's keys of Capri's aren't hers: {shown} against {set(capri)}"

# Every shortcut on the manual's shortcuts page is one of these (an update that moved one left the page naming a key
# that does nothing). Its cells as written: "Print, Super+Shift+S" each, "Super+1...0" the digits, "/" either key
# ("Super+PageUp/PageDown"; "Ctrl+Super+= / -" the second with the first's modifiers), "Super" alone the launcher's
import itertools
import re
words = {"super": "SUPER", "ctrl": "CTRL", "alt": "ALT", "shift": "SHIFT", "esc": "Escape", "del": "Delete",
         ".": "Period", "=": "Equal", "-": "Minus", "pageup": "Page_Up", "pagedown": "Page_Down"}


def combos(cell):
    mods, sep = [], ","
    for one in re.split(r"(,\s*|\s+/\s+)", re.sub(r"\s*\(.*?\)", "", cell).strip()):
        if one.strip() in (",", "/"):
            sep = one.strip()
            continue
        if one.lower() == "super":
            yield ["SUPER + SUPER_L"]
            continue
        parts = one.split("+")
        if len(parts) > 1:
            mods = parts[:-1]
        elif sep == "/":
            parts = mods + parts
        choices = []
        for p in parts:
            alts = list("1234567890") if p == "1...0" else p.split("/")
            alts = [x for a in alts for x in (["mouse_down", "mouse_up"] if a.lower() == "scroll"
                                              else [words.get(a.lower(), a)])]
            choices.append(alts)
        yield [" + ".join(pick) for pick in itertools.product(*choices)]


listed, missing = 0, []
for line in open(f"{here}/manual/06-shortcuts.md", encoding="utf-8"):
    cell = line.split("|")[1].strip() if line.startswith("| ") else ""
    if cell in ("", "Shortcut") or set(cell) <= set("-"):
        continue
    for keys in combos(cell):
        listed += len(keys)
        missing += [f"{k} ({cell})" for k in keys if norm(k) not in used]
assert listed > 50, f"the shortcuts page read as {listed} keys: is it still a table?"
assert not missing, f"the manual's shortcuts page lists keys nothing is bound to: {missing}"
P
echo "ok dots-settings-keys"
