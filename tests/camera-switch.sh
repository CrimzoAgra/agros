#!/usr/bin/env bash
# The camera switch's saved position (camera-switchd, its state file in a stand-in folder): written whole (beside it,
# then renamed over it: never an empty file), and read as on only when it says on, anything else (off, empty, broken,
# none) off; the udev rule reads it the same way (on, or the camera taken out)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
c=$here/.local/share/camera-switch
python3 -I - "$c/camera-switchd" "$t" <<'P' || fail "camera-switchd's saved position"
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("cs", sys.argv[1])
cs = importlib.util.module_from_spec(importlib.util.spec_from_loader("cs", loader))
loader.exec_module(cs)
cs.STATE = f"{sys.argv[2]}/state/state"
cs.camera_dir = lambda: None  # (no camera here: only the position written)
for on in (False, True, False):
    cs.apply(on, announce=False)
    assert open(cs.STATE).read() == ("on" if on else "off"), open(cs.STATE).read()
    assert not os.path.exists(cs.STATE + ".new"), "the file written beside it left there"
for text, want in (("on", True), ("on\n", True), ("off", False), ("", False), ("garbage", False)):
    open(cs.STATE, "w").write(text)
    assert cs.saved_on() is want, f"{text!r} read as {cs.saved_on()}"
os.remove(cs.STATE)
assert cs.saved_on() is False, "no saved position read as on"
P
rule=$(grep -o "RUN+=\"[^\"]*\"" "$here/packages/agros-camera-switch/90-agros-camera-switch.rules")
sh_cmd=${rule#*-c \'}; sh_cmd=${sh_cmd%\'\"}
for text in on off "" garbage; do
    printf '%s' "$text" >"$t/udev-state"; : >"$t/authorized"
    cmd=${sh_cmd//\/var\/lib\/camera-switch\/state/$t/udev-state}
    sh -c "${cmd//\/sys%p\/authorized/$t/authorized}" 2>/dev/null || true
    if [[ $text == on ]]; then [[ ! -s $t/authorized ]] || fail "udev: the camera taken out with the switch on"
    else [[ $(cat "$t/authorized") == 0 ]] || fail "udev: the camera left in with the saved position '$text'"; fi
done
echo "ok camera-switch"
