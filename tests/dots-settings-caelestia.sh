#!/usr/bin/env bash
# The Settings app's Caelestia options, read from the Caelestia installed here (caelestia-options.qml, through Qt's qml
# tool): every option listed with a control for its kind, a choice with its names; every one the schema's own pages
# name is one this Caelestia has (else it's silently left out); a change written to shell.json through json-edit, back
# to the default leaving the option out, or putting AgrOS's own value back where it ships one; one AgrOS manages
# refused; a value of the wrong kind refused. Without Caelestia (or an older one), no Caelestia options and the rest
# works; a failing option read not cached (only an older Caelestia's none), nor waited out; an option on a page and in
# "All Caelestia options" keeps the page's range; now (the app's poll) the schema's values without its
# option lists. The other new kinds:
# numbers kept in their range, Caelestia's variables and the screens' settings in settings.lua only once changed (a
# screen's kept while it's unplugged), a screen's position only as WxH, its scales only those that give whole pixels
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/caelestia" "$t/skel"
# Your file (an option by its number, as Caelestia also reads it) and AgrOS's copy (notifs.fullscreen: "Off")
echo '{"services": {"clockFormat": 2}}' >"$t/caelestia/shell.json"
echo '{"notifs": {"fullscreen": "Off"}}' >"$t/skel/shell.json"
# (77: no Caelestia option list to check against, said below: a part skipped, a failure on CI)
python3 -I - "$here" "$t" <<'P' || { rc=$?; ((rc == 77)) || exit "$rc"; skipped "no Caelestia option list here (Caelestia or Qt's qml tool missing, or an older Caelestia): its options not checked"; }
import contextlib, importlib.machinery, importlib.util, io, json, os, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.SCHEMA, ds.CONFIG, ds.SETTINGS = f"{here}/.local/share/dots-settings/schema.json", f"{t}/dots", f"{t}/dots/settings.json"
ds.CAELESTIA_DIR, ds.SHIPPED_DIR, ds.HERE = f"{t}/caelestia", f"{t}/skel", f"{here}/.local/bin"
ds.OPTIONS_QML, ds.CACHE = f"{here}/.local/share/dots-settings/caelestia-options.qml", f"{t}/cache/options.json"
ds.AUTOSTART, ds.PATCHES = [], {}


def run(*args):
    ds._files.clear()  # (each command its own run: Caelestia's files read again)
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            ds.main(list(args))
    except SystemExit as e:
        return f"error: {e.code}"
    return out.getvalue()


def shell():
    with open(f"{t}/caelestia/shell.json") as f:
        return json.load(f)


# An option the reader gave no default for (JSON leaves an undefined value out): shown with none, not every page's
# schema failing on it
s = ds.caelestia_setting("caelestia-shell", {"key": "some.option", "type": "bool"})
assert s["type"] == "bool" and s["caelestia_default"] is None, s
# Numbers: in their range; Caelestia's variables and the screens' settings only once changed, a screen's kept unplugged
assert run("set", "input.repeat_rate", "500", "--later").startswith("error"), "a number out of its range taken"
assert run("set", "input.repeat_rate", "40.0", "--later") == "hypr\n"
assert json.load(open(ds.SETTINGS))["input.repeat_rate"] == 40, "a whole number not saved as one"
json.dump({"screens.Gone Screen 1.scale": "2"}, open(ds.SETTINGS, "w"))
run("set", "input.repeat_rate", "40", "--later")
lua = open(f"{t}/dots/settings.lua").read()
assert '["screens.Gone Screen 1.scale"] = "2"' in lua, "an unplugged screen's setting lost"
assert "caelestia-vars." not in lua, "Caelestia's variables written unchanged (an update's new default never reached)"
# A screen's position: WxH in whole pixels or empty (Automatic), nothing else reaching Hyprland's monitor rule
real_hyprctl = ds.hyprctl
ds.hyprctl = lambda *a: [{"description": "Some Screen 1", "name": "DP-1", "make": "M", "model": "S", "width": 1920,
                          "height": 1080, "refreshRate": 60.0, "scale": 1.0}] if a[0] == "monitors" else []
pos = "screens.Some Screen 1.position"
for bad in ('"1920x"', '"1920,0"', '"a1920x0"', '"1920.5x0"', '"-1920x0"', '"0x-1080"'):
    assert run("set", pos, bad, "--later").startswith("error"), f"position {bad} taken"
assert run("set", pos, '"1920x0"', "--later") == "hypr\n" and run("set", pos, '""', "--later") == "hypr\n"
# A screen's scales: only those that give it a whole size in pixels (Hyprland refuses the others: 1.75 on 1920x1080),
# the one set kept all the same (set before, or for another mode)
scale = "screens.Some Screen 1.scale"


def offered():
    return [o["value"] for o in ds.all_settings(ds.schema(lists=False))[scale]["options"]]


assert "1.75" not in offered() and "1.5" in offered() and "2" in offered(), offered()
assert run("set", scale, '"1.75"', "--later").startswith("error"), "a scale Hyprland refuses taken"
assert run("set", scale, '"1.25"', "--later") == "hypr\n", "a scale that fits refused"
saved = json.load(open(ds.SETTINGS))
saved[scale] = "1.75"
json.dump(saved, open(ds.SETTINGS, "w"))
assert offered() == ["", "1", "1.25", "1.5", "1.6", "1.75", "2"], f"the scale set no longer offered: {offered()}"
assert json.loads(run("get", scale)) == "1.75", "the scale set read as the default"
# A screen with no description (a VM's, with no EDID): listed all the same, its settings by its connector's name, as
# user/monitors.lua reads them. None from Hyprland said as that, not as no Hyprland session
ds.hyprctl = lambda *a: [{"description": "", "name": "Virtual-1", "make": "", "model": "", "serial": "", "width": 2258,
                          "height": 1359, "refreshRate": 60.0, "scale": 1.0}] if a[0] == "monitors" else []
vm = ds.screens_groups()
assert len(vm) == 1 and vm[0]["title"] == "Virtual-1 (now 2258x1359 at 60 Hz, scale 1)", vm
assert vm[0]["settings"][0]["key"] == "screens.Virtual-1.enabled", vm[0]["settings"][0]
assert run("set", "screens.Virtual-1.scale", '"1"', "--later") == "hypr\n", "a screen with no description not set"
assert '["screens.Virtual-1.scale"] = "1"' in open(f"{t}/dots/settings.lua").read(), "its setting not in settings.lua"
ds.hyprctl = lambda *a: []
assert ds.screens_groups()[0]["empty"] == "No screens found (Hyprland reported none)", ds.screens_groups()
ds.hyprctl = lambda *a: None
assert ds.screens_groups()[0]["empty"] == "No screens found (not in a Hyprland session)", ds.screens_groups()
ds.hyprctl = real_hyprctl

options = ds.caelestia_options()
if not os.path.exists(ds.QML) or not options:
    sys.exit(77)
settings = ds.all_settings(ds.schema())
mine = [k for k in settings if k.startswith(tuple(ds.CAELESTIA_FILES))]
assert len(options["caelestia-shell"]) > 100, f"only {len(options['caelestia-shell'])} Caelestia options read"
listed = sum(len(o) for o in options.values())
assert len(mine) >= listed, f"{listed} options, {len(mine)} listed"
for k in mine:
    s = settings[k]
    assert s["type"] in ("bool", "number", "choice", "text", "json"), (k, s["type"])
    assert s["type"] != "choice" or s.get("open") or s["default"] in [o["value"] for o in s["options"]], (k, s["default"])
# Every option the hand-written pages name is in this Caelestia (a renamed one would quietly vanish from its page)
with open(ds.SCHEMA) as f:
    named = [s["key"] for p in json.load(f)["pages"] for g in p["groups"] for s in g.get("settings", [])
             if s["key"].startswith(tuple(ds.CAELESTIA_FILES))]
found = {f"{p}.{o['key']}" for p, opts in options.items() for o in opts}
assert not set(named) - found, f"not options of the Caelestia installed: {sorted(set(named) - found)}"

# Options whose names end in "Changed" are options too (only signals are skipped)
with open(f"{ds.CAELESTIA_CONFIG}/caelestia-config.qmltypes") as f:
    if 'name: "capsLockChanged"' in f.read():
        assert "caelestia-shell.utilities.toasts.capsLockChanged" in found, "an option ending in Changed left out"
# One on a page of its own and in "All Caelestia options": the page's range holds (it's the one set checks), and both
# copies come out of schema with their value
assert run("set", "caelestia-shell.border.thickness", "500").startswith("error"), "a curated range not enforced"
copies = [s for p in json.loads(run("schema"))["pages"] for g in p["groups"] for s in g["settings"]
          if s["key"] == "caelestia-shell.border.thickness"]
assert len(copies) == 2 and all("value" in s and s.get("max") == 40 for s in copies), copies
# The Settings app's poll (now): every value the schema has but the shortcut list's (a connected screen's too), none of
# the option lists' commands run
ds.hyprctl = lambda *a: [{"description": "Some Screen 1", "name": "DP-1", "make": "M", "model": "S", "width": 1920,
                          "height": 1080, "refreshRate": 60.0, "scale": 1.0,
                          "availableModes": ["1920x1080@60.00Hz"]}] if a[0] == "monitors" else []
full = {s["key"]: s["value"] for p in json.loads(run("schema"))["pages"] for g in p["groups"] for s in g["settings"]
        if not s["key"].startswith("binds.")}
ran, real = [], ds.options_from
ds.options_from = lambda cmd: ran.append(cmd) or []
assert any(k.startswith("screens.Some Screen 1.") for k in full), "no screen in the schema to compare with"
assert json.loads(run("now")) == full, "now's values aren't the schema's"
ds.options_from, ds.hyprctl = real, real_hyprctl
assert not ran, f"now ran the option lists' commands: {ran}"
# A qml run that fails (an error before its Qt.quit) ends at once, not at the timeout, and isn't cached (tried again
# next time); a Caelestia too old to describe its options (no descriptorFor) is cached until something changes
import shutil, time
bad = f"{t}/bad-options.qml"
src = open(ds.OPTIONS_QML).read()
open(bad, "w").write(src.replace('walk(GlobalConfig, "", [])', 'walk(undefined.x, "", [])'))
saved_qml, saved_cache = ds.OPTIONS_QML, ds.CACHE
ds.OPTIONS_QML, ds.CACHE = bad, f"{t}/cache/bad.json"
began = time.monotonic()
assert ds.caelestia_options() == {}
assert time.monotonic() - began < 20, "a failing qml run waited for the timeout"
assert not os.path.exists(ds.CACHE), "a failed read cached (kept until Caelestia changes)"
ds.OPTIONS_QML = f"{t}/missing.qml"
assert ds.caelestia_options() == {} and not os.path.exists(ds.CACHE), "a missing reader's result cached"
ds.OPTIONS_QML = bad
open(bad, "w").write(src.replace('walk(GlobalConfig, "", [])', 'walk({ a: {} }, "", [])'))
assert ds.caelestia_options() == {} and json.load(open(ds.CACHE))["options"] == {}, "an old Caelestia's {} not cached"
ds.QML = "/nonexistent"  # (cached: not run again)
assert ds.caelestia_options() == {} and json.load(open(ds.CACHE))["stamp"]
c = json.load(open(ds.CACHE))
json.dump({**c, "options": {"marker": []}}, open(ds.CACHE, "w"))
assert ds.caelestia_options() == {"marker": []}
os.utime(bad, ns=(0, 0))  # (the reader changed: what it read before isn't used)
assert ds.caelestia_options() == {}, "a cache read by an older reader used"
ds.OPTIONS_QML, ds.CACHE = saved_qml, saved_cache
ds.QML = "/usr/lib/qt6/bin/qml"

# A choice as Caelestia's number shows by its name; AgrOS's value is the default where it ships one
clock = "caelestia-shell.services.clockFormat"
assert ds.values(settings)[clock] == "TwentyFourHour", ds.values(settings)[clock]
assert settings["caelestia-shell.notifs.fullscreen"]["default"] == "Off", "AgrOS's value not the default"
# A change written to shell.json; back to Caelestia's default: left out (a Caelestia update's new one reaches it)
assert run("set", "caelestia-shell.bar.persistent", "false") == ""
assert shell()["bar"]["persistent"] is False and shell()["services"]["clockFormat"] == 2, shell()
run("set", "caelestia-shell.bar.persistent", "true")
assert "persistent" not in shell()["bar"], shell()
# ...but where AgrOS ships its own, that one written back
run("set", "caelestia-shell.notifs.fullscreen", '"On"')
run("set", "caelestia-shell.notifs.fullscreen", '"Off"')
assert shell()["notifs"]["fullscreen"] == "Off", shell()
# Sizes go to shell-tokens.json
tok = next(k for k in mine if k.startswith("caelestia-tokens.") and settings[k]["type"] == "number")
run("set", tok, "3")
assert json.load(open(f"{t}/caelestia/shell-tokens.json")), "a size not written to shell-tokens.json"
# Refused: one AgrOS manages, the wrong kind, a choice that isn't one
assert run("set", "caelestia-shell.launcher.favouriteApps", "[]").startswith("error"), "a managed option changed"
assert run("set", "caelestia-shell.bar.persistent", '"yes"').startswith("error")
assert run("set", "caelestia-shell.launcher.hiddenApps", '"x"').startswith("error"), "JSON of the wrong kind taken"
assert run("set", clock, '"Sundial"').startswith("error")
# A shell.json that isn't JSON (a hand edit): left as it is, the change refused
open(f"{t}/caelestia/shell.json", "w").write("{broken")
assert run("set", "caelestia-shell.bar.persistent", "false").startswith("error")
assert open(f"{t}/caelestia/shell.json").read() == "{broken", "a broken shell.json overwritten"

# Without Caelestia: none of its options, the rest as before
ds.CAELESTIA_CONFIG, ds.CACHE = f"{t}/nothing", f"{t}/cache/none.json"
rest = ds.all_settings(ds.schema())
assert not [k for k in rest if k.startswith(tuple(ds.CAELESTIA_FILES))] and "windows.cascade" in rest
P
echo "ok dots-settings-caelestia"
