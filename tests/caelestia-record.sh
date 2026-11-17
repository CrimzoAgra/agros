#!/usr/bin/env bash
# The screen recorder (caelestia record: Ctrl+Alt+R, the quick settings' recorder) falls back to encoding on the CPU:
# AgrOS's cli.json gives gpu-screen-recorder -fallback-cpu-encoding yes, as Caelestia's command reads it. Without it a
# machine with no hardware video encoder (a VM) only got "Recording failed". The file parses, and the command
# installed here (caelestia-cli) passes the option on to the recorder it starts
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/home/.config/caelestia"
cp "$here/.config/caelestia/cli.json" "$t/home/.config/caelestia/"
python3 -I - "$t/home/.config/caelestia/cli.json" <<'P'
import json, sys
extra = json.load(open(sys.argv[1]))["record"]["extraArgs"]
assert isinstance(extra, list) and all(isinstance(a, str) for a in extra), extra
assert any(extra[i:i + 2] == ["-fallback-cpu-encoding", "yes"] for i in range(len(extra))), extra
P
# (77: no caelestia-cli here to run)
rc=0
HOME=$t/home python3 -I - <<'P' || rc=$?
import subprocess, sys
from argparse import Namespace
try:
    from caelestia.subcommands import record
except ImportError:
    sys.exit(77)
started = []


class Recorder:  # (gpu-screen-recorder's stand-in: still running a second later, as a started recording is)
    def __init__(self, args, **_):
        self.args, self.returncode = args, None
        started.append(args)

    def wait(self, timeout=None):
        raise subprocess.TimeoutExpired(self.args, timeout)


record.subprocess.Popen = Recorder
record.hypr.message = lambda *a, **k: [{"name": "Virtual-1", "focused": True, "refreshRate": 60.0}]
record.notify = lambda *a, **k: "1"
record.close_notification = lambda *a, **k: None
record.Command(Namespace(region=None, sound=False, pause=False, clipboard=False)).start()
assert started and started[0][0] == "gpu-screen-recorder", started
args = started[0]
assert any(args[i:i + 2] == ["-fallback-cpu-encoding", "yes"] for i in range(len(args))), \
    f"caelestia record didn't pass cli.json's option on: {args}"
P
case $rc in
    0) ;;
    77) skipped "caelestia-cli not installed: its recorder's command not checked" ;;
    *) fail "caelestia record: see above" ;;
esac
echo "ok caelestia-record"
