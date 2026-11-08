#!/usr/bin/env bash
# dots-settings' autostart entries: turning one off and on again starts it again, also when your copy only hid the
# system's (the repo's cachyos-hello.desktop: Hidden=true and no Exec=, which still replaces the system's entry)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
python3 -I - "$here" "$t" <<'P'
import importlib.machinery, importlib.util, os, sys
here, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
system, mine = f"{t}/xdg", f"{t}/home/autostart"
os.makedirs(system)
ds.AUTOSTART = [system, mine]
open(f"{system}/hello.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Hello\nExec=hello\nIcon=hello\n")

def starts(name):
    """What an XDG autostart runs: your copy if there is one (whatever it holds), else the system's"""
    path = f"{mine}/{name}" if os.path.exists(f"{mine}/{name}") else f"{system}/{name}"
    entry = ds.desktop_entry(path)
    return entry.get("Hidden") != "true" and bool(entry.get("Exec"))

# Off, then on: a full copy written, then removed again (the system's own entry, its later updates too)
ds.autostart_set("hello.desktop", False)
assert not ds.autostart_on("hello.desktop") and not starts("hello.desktop"), "turned off, still starts"
ds.autostart_set("hello.desktop", True)
assert ds.autostart_on("hello.desktop") and starts("hello.desktop"), "turned on again, doesn't start"
assert not os.path.exists(f"{mine}/hello.desktop"), "turned on again, your copy still shadows the system's entry"
# Your copy only hiding the system's: on means the system's entry starts again
open(f"{mine}/hello.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Hello\nHidden=true\n")
assert not ds.autostart_on("hello.desktop")
ds.autostart_set("hello.desktop", True)
assert ds.autostart_on("hello.desktop"), "shown off after turning it on"
assert starts("hello.desktop"), "turned on, but your copy (no Exec=) still replaces the system's entry: nothing starts"
# An entry only you have (no system one): turning it on keeps it
open(f"{mine}/own.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Own\nExec=own\nHidden=true\n")
ds.autostart_set("own.desktop", True)
assert starts("own.desktop"), "your own entry lost turning it on"
# One the system ships switched off: shown off (it doesn't start); a header with spaces after it: turned off all the same
open(f"{system}/off.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Off\nExec=off\nX-GNOME-Autostart-enabled=false\n")
assert not ds.autostart_on("off.desktop"), "an entry the system ships switched off shown on"
# ...and turning it on starts it (only a copy of yours can), also when your copy had only hidden it
ds.autostart_set("off.desktop", True)
assert ds.autostart_on("off.desktop") and starts("off.desktop"), "one the system ships off, turned on, still off"
ds.autostart_set("off.desktop", False)
assert not ds.autostart_on("off.desktop") and not starts("off.desktop"), "turned off again, still starts"
open(f"{mine}/off.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Off\nHidden=true\n")
ds.autostart_set("off.desktop", True)
assert ds.autostart_on("off.desktop") and starts("off.desktop"), "your hiding copy of one shipped off: turned on, nothing starts"
open(f"{system}/spaced.desktop", "w").write("[Desktop Entry]  \nType=Application\nName=Spaced\nExec=spaced\n")
ds.autostart_set("spaced.desktop", False)
assert not ds.autostart_on("spaced.desktop"), "an entry with spaces after its header not turned off"
P
echo "ok dots-settings-autostart"
