#!/usr/bin/env bash
# dots-settings' saved choices: a broken settings.json (not JSON, or not an object) reads as the defaults instead of
# failing every read, but a change refuses to write over it (every other setting in it went with it); a value that
# isn't JSON, or a number that's NaN or Infinity, is refused with a message (a whole number's NaN crashed it); a change
# keeps the other saved ones
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
python3 -I - "$here" "$t" <<'P'
import contextlib, importlib.machinery, importlib.util, io, json, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.CACHE, ds.CAELESTIA_DIR = f"{t}/caelestia-options.json", f"{t}/caelestia"  # (not your home's)
ds.OPTIONS_QML = f"{here}/.local/share/dots-settings/caelestia-options.qml"  # (the repo's, not your home's)
ds.SCHEMA, ds.CONFIG, ds.SETTINGS = f"{here}/.local/share/dots-settings/schema.json", t, f"{t}/settings.json"
ds.PATCHES = {"caelestia": f"{here}/.local/share/caelestia-overlay/patch.py", "lutris": f"{here}/.local/share/lutris-overlay/patch.py"}
# (Caelestia's shortcuts from a home of the test's own: dots-settings reads the account's home, root's in CI, with none)
import os
os.makedirs(f"{t}/.config/hypr"); os.makedirs(f"{t}/.config/caelestia")
open(f"{t}/.config/hypr/variables.lua", "w").write(
    '-- KEYBINDS\nkbGoToWs = "SUPER"\n-- All the following binds\nkbClearNotifs = "CTRL + ALT + C"\n')
open(f"{t}/.config/caelestia/hypr-vars.lua", "w").close()
ds.HOME = t
settings = ds.all_settings(ds.schema())
b = [k for k, s in settings.items() if s["type"] == "bool" and "get" not in s and "autostart" not in s][:2]


def run(*args):
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            ds.main(list(args))
    except SystemExit as e:
        return str(e.code)
    return out.getvalue()


for broken in ("{not json", "[1, 2]", "null"):
    open(ds.SETTINGS, "w").write(broken)
    assert ds.values(settings)[b[0]] == settings[b[0]]["default"], f"broken file {broken!r}: not the default"
    # ...and not written over by a change (every other setting in it went with it)
    err = run("set", b[0], json.dumps(not settings[b[0]]["default"]), "--later")
    assert "isn't valid settings" in err and open(ds.SETTINGS).read() == broken, f"broken file {broken!r} written over: {err!r}"
os.remove(ds.SETTINGS)
err = run("set", b[0], "notjson", "--later")
assert err.startswith(b[0] + ":"), f"a value that isn't JSON: {err!r}"
n = next(k for k, s in settings.items() if s["type"] == "number" and s.get("integer") and "get" not in s)
for odd in ("NaN", "Infinity", "-Infinity"):
    err = run("set", n, odd, "--later")
    assert err.startswith(n + ": a whole number"), f"{odd} for {n}: {err!r}"
assert not ds.stored().get(n), f"a NaN or Infinity saved: {ds.stored()}"
run("set", b[0], json.dumps(not settings[b[0]]["default"]), "--later")
run("set", b[1], json.dumps(not settings[b[1]]["default"]), "--later")
saved = json.load(open(ds.SETTINGS))
assert set(saved) == {b[0], b[1]}, f"a change lost another: {saved}"
# A setting changed by its own command (hyprctl eval prints "ok"): --later's stdout only how to apply it, the Settings
# app's word for it; the command's output on stderr. Read at the descriptor: the command writes there, not to sys.stdout
import os, tempfile
noisy = {"key": "t.noisy", "type": "bool", "default": False, "label": "Noisy", "set": "echo ok", "apply": "hypr"}
ds.schema = lambda **_: {"pages": [{"groups": [{"settings": [noisy]}]}]}
with tempfile.TemporaryFile("w+") as out, tempfile.TemporaryFile("w+") as err:
    sys.stdout.flush(); sys.stderr.flush()
    keep = os.dup(1), os.dup(2)
    os.dup2(out.fileno(), 1); os.dup2(err.fileno(), 2)
    try:
        ds.main(["set", "t.noisy", "true", "--later"])
        sys.stdout.flush(); sys.stderr.flush()
    finally:
        os.dup2(keep[0], 1); os.dup2(keep[1], 2)
    out.seek(0); err.seek(0)
    said, errs = out.read(), err.read()
assert said == "hypr\n", f"a set command's output in --later's: {said!r}"
assert "ok" in errs, f"a set command's output lost: {errs!r}"
P
echo "ok dots-settings-store"
