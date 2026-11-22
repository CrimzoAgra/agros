#!/usr/bin/env bash
# The camera switch's saved position (camera-switchd, its state file in a stand-in folder): written whole (beside it,
# then renamed over it: never an empty file), and read as on only when it says on, anything else (off, empty, broken,
# none) off; the udev rule reads it the same way (on, or the camera taken out). Its notification run as the user's own
# group (the account's, not the bus file's), and never waited on by the switch
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
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
# A write to the camera that fails (re-appearing on the bus after a resume): the position saved all the same, for the
# udev rule to apply as it comes back (saved after it, the old "on" stayed: the camera back with the switch off)
cs.apply(True, announce=False)
cs.camera_dir = lambda: f"{sys.argv[2]}/gone"
cs.apply(False, announce=False)
assert open(cs.STATE).read() == "off", "a failed write to the camera left the old position saved"
cs.camera_dir = lambda: None
# notify: the group from the account, never the bus file's (a user's bus a link to a root-group file gave group root);
# a bus not owned by the uid in its path skipped
import pwd, types
uid = os.getuid()
for u in (uid, 0):
    os.makedirs(f"{sys.argv[2]}/run/{u}")
os.symlink("/etc/passwd", f"{sys.argv[2]}/run/{uid}/bus")
open(f"{sys.argv[2]}/run/0/bus", "w").close()
calls = []
def run(args, **kw):
    calls.append(args)
    return types.SimpleNamespace(stdout=f"{sys.argv[2]}/run/{uid}/bus {sys.argv[2]}/run/0/bus\n")
cs.subprocess.run = run
cs.notify(True)
sp = [c for c in calls if c[0] == "setpriv"]
assert len(sp) == 1 and sp[0][1:3] == [f"--reuid={uid}", f"--regid={pwd.getpwuid(uid).pw_gid}"], sp
# The switch never waits on its notification (one that hangs, a frozen desktop's bus, held its next move: the camera
# left on with the switch off): the positions queued for the announcer, in order
import time
cs.subprocess.run = lambda *a, **k: time.sleep(6)
start = time.monotonic()
cs.apply(True, announce=True)
cs.apply(False, announce=True)
assert time.monotonic() - start < 5, "the switch waited on its notification"
assert [cs.said.get_nowait(), cs.said.get_nowait()] == [True, False], "the positions not queued in order"
assert open(cs.STATE).read() == "off"
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
