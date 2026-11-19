#!/usr/bin/env bash
# dots-settings' saved choices: a broken settings.json (not JSON, or not an object) reads as the defaults instead of
# failing every read; a value that isn't JSON, or a number that's NaN or Infinity, is refused with a message (a whole
# number's NaN crashed it); a change keeps the other saved ones
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
settings = ds.all_settings(ds.schema())
b = [k for k, s in settings.items() if s["type"] == "bool" and "get" not in s and "autostart" not in s][:2]
for broken in ("{not json", "[1, 2]", "null"):
    open(ds.SETTINGS, "w").write(broken)
    assert ds.values(settings)[b[0]] == settings[b[0]]["default"], f"broken file {broken!r}: not the default"


def run(*args):
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            ds.main(list(args))
    except SystemExit as e:
        return str(e.code)
    return out.getvalue()


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
# Capri's fixed keys (she binds them herself while she runs) shown read-only on the Shortcuts page, and refused for any
# other shortcut, AgrOS's or Caelestia's, in any order and case, with a message (the Settings app shows a refused
# change's): with them, Hyprland and she both acted on the keys
page = next(p for p in ds.schema()["pages"] if p["id"] == "keys")
capri = {k for g in page["groups"] for s in g["settings"] if s.get("reserved") == "Capri's" and s.get("readonly")
         for k in s["default"]}
assert capri == {"CTRL + ALT + Space", "CTRL + ALT + SHIFT + Space", "CTRL + ALT + K", "CTRL + ALT + X"},     f"Capri's keys not on the Shortcuts page: {capri}"
k = next(k for k, s in settings.items() if k.startswith("keys.") and not s.get("modifier") and "get" not in s)
err = run("set", k, json.dumps(settings[k]["default"] + ["alt + ctrl + k"]), "--later")
assert err.startswith(k + ": CTRL + ALT + K is Capri's (her chat)"), f"Capri's chat key taken by {k}: {err!r}"
m = next(k for k, s in settings.items() if s.get("modifier") and "get" not in s)
err = run("set", m, json.dumps(["CTRL + ALT"]), "--later")
assert not err.startswith(m + ":"), f"a modifier for 0-9 with Capri's modifiers refused: {err!r}"
err = run("set", "capri-keys.chat", json.dumps(["SUPER + K"]), "--later")
assert err.startswith("capri-keys.chat:"), f"Capri's own key changed: {err!r}"
assert k not in ds.stored() and "capri-keys.chat" not in ds.stored(), f"saved: {ds.stored()}"
run("set", m, json.dumps(settings[m]["default"]), "--later")
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
