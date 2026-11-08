#!/usr/bin/env bash
# dots-settings' saved choices: a broken settings.json (not JSON, or not an object) reads as the defaults instead of
# failing every read; a value that isn't JSON is refused with a message; a change keeps the other saved ones
set -euo pipefail
. "$(dirname "$0")/lib.sh"
python3 -I - "$here" "$t" <<'P'
import contextlib, importlib.machinery, importlib.util, io, json, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
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
run("set", b[0], json.dumps(not settings[b[0]]["default"]), "--later")
run("set", b[1], json.dumps(not settings[b[1]]["default"]), "--later")
saved = json.load(open(ds.SETTINGS))
assert set(saved) == {b[0], b[1]}, f"a change lost another: {saved}"
P
echo "ok dots-settings-store"
