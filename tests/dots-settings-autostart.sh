#!/usr/bin/env bash
# dots-settings' autostart entries: turning one off and on again starts it again, also when your copy only hid the
# system's (Hidden=true and no Exec=, which still replaces the system's entry); Startup's "Add an app" adds one and
# switching it off takes it out
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
# Startup's "Add an app": the installed apps in the menus, not terminal ones nor ones listed already; picked, it's
# listed and starts (even without an icon); switched off, it's gone from the list and offered again. Ones AgrOS knows
# start quietly
apps = f"{t}/apps"
os.makedirs(apps)
ds.APPLICATIONS = [apps]
open(f"{apps}/editor.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Editor\nExec=editor %F\nNoDisplay=false\n\n[Desktop Action new]\nName=New\nExec=editor --new\n")
open(f"{apps}/top.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Top\nExec=top\nTerminal=true\n")
open(f"{apps}/helper.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Helper\nExec=helper\nNoDisplay=true\n")
open(f"{apps}/hello.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Hello\nExec=hello\n")
offered = lambda: [a["value"] for a in ds.startup_apps()]
assert offered() == ["editor.desktop"], f"offered {offered()}"
ds.startup_add("editor.desktop")
assert starts("editor.desktop"), "added, doesn't start"
assert "autostart.editor" in [s["key"] for s in ds.autostart_settings()], "added, not listed"
assert "editor.desktop" not in offered(), "added, still offered"
ds.autostart_set("editor.desktop", False)
assert not os.path.exists(f"{mine}/editor.desktop"), "one you added, switched off, still listed"
assert offered() == ["editor.desktop"], "switched off, not offered again"
# One AgrOS knows starts quietly (Lutris: in its tray, no window): its entry's own Exec swapped, not its actions'
open(f"{apps}/net.lutris.Lutris.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Lutris\nExec=lutris %U\n\n[Desktop Action x]\nName=X\nExec=lutris --x\n")
ds.startup_add("net.lutris.Lutris.desktop")
text = open(f"{mine}/net.lutris.Lutris.desktop").read()
assert "\nExec=sh -c \"gdbus wait --session --timeout 60 org.kde.StatusNotifierWatcher; exec env LUTRIS_START_HIDDEN=1 lutris\"\n" in text \
    and "Exec=lutris --x" in text, text
# migrate: an account from before the Startup rework gets its old switches as entries (Lutris and Capri were on unless
# turned off), once; the old keys go, the night light's becomes its own. An entry added with an older quiet start gets
# the new one. A new account gets none, then or later
import json
ds.write_lua = lambda settings: None
ds.CONFIG = f"{t}/config"
ds.SETTINGS = f"{ds.CONFIG}/settings.json"
os.makedirs(ds.CONFIG)
for name in ("proton.vpn.app.gtk.desktop", "capri.desktop"):
    open(f"{apps}/{name}", "w").write(f"[Desktop Entry]\nType=Application\nName={name}\nExec=x\n")
os.remove(f"{mine}/net.lutris.Lutris.desktop")
json.dump({"startup.protonvpn": True, "startup.capri": False, "startup.nightlight": True, "x": 1}, open(ds.SETTINGS, "w"))
ds.migrate({}, True)
assert sorted(n for n in os.listdir(mine) if n in ds.LOGIN_EXEC) == ["net.lutris.Lutris.desktop", "proton.vpn.app.gtk.desktop"], os.listdir(mine)
assert json.load(open(ds.SETTINGS)) == {"nightlight": True, "x": 1}, open(ds.SETTINGS).read()
assert "--start-minimized" in ds.desktop_entry(f"{mine}/proton.vpn.app.gtk.desktop")["Exec"]
os.remove(f"{mine}/net.lutris.Lutris.desktop")  # (switched off since: stays off)
stale = open(f"{mine}/proton.vpn.app.gtk.desktop").read().replace("--start-minimized", "")
open(f"{mine}/proton.vpn.app.gtk.desktop", "w").write(stale)
ds.migrate({}, True)
assert not os.path.exists(f"{mine}/net.lutris.Lutris.desktop"), "migrated twice: an app switched off came back"
assert ds.desktop_entry(f"{mine}/proton.vpn.app.gtk.desktop")["Exec"] == ds.LOGIN_EXEC["proton.vpn.app.gtk.desktop"], "an older quiet start kept"
os.remove(f"{ds.CONFIG}/.startup-moved")
os.remove(f"{mine}/proton.vpn.app.gtk.desktop")
ds.migrate({}, False)
ds.migrate({}, True)
assert not os.path.exists(f"{mine}/net.lutris.Lutris.desktop"), "a new account got AgrOS's old presets"
# Startup's list: your apps only, each minimised or open normally, and removable. The system's entries (the print
# queue applet) not listed; one added before the choice: minimised when AgrOS knew a quiet start for it, else normal
open(f"{system}/print-applet.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Print Queue Applet\nExec=applet\nIcon=printer\n")
listed = lambda: {s["autostart"]: s for s in ds.autostart_settings()}
assert "print-applet.desktop" not in listed(), "the system's print queue applet listed among your apps"
ds.startup_add("net.lutris.Lutris.desktop")
old = open(f"{mine}/net.lutris.Lutris.desktop").read()
open(f"{mine}/net.lutris.Lutris.desktop", "w").write("".join(l + "\n" for l in old.splitlines() if not l.startswith("X-AgrOS-Startup-Mode=")))
assert ds.autostart_mode("net.lutris.Lutris.desktop") == "minimised", "Lutris added before the choice not read as minimised"
ds.startup_add("editor.desktop", False)
assert ds.autostart_mode("editor.desktop") == "normal" and ds.desktop_entry(f"{mine}/editor.desktop")["Exec"] == "editor %F", \
    open(f"{mine}/editor.desktop").read()
s = listed()["editor.desktop"]
assert s["type"] == "startup" and [o["value"] for o in s["options"]] == ["minimised", "normal"], s
# Minimised: an app AgrOS has no quiet start for marked for user/apps.lua; normal again: its own command back
ds.startup_add("editor.desktop", True)
assert ds.desktop_entry(f"{mine}/editor.desktop")["Exec"] == "env AGROS_START_MINIMISED=1 editor %F", open(f"{mine}/editor.desktop").read()
ds.startup_add("editor.desktop", False)
assert ds.desktop_entry(f"{mine}/editor.desktop")["Exec"] == "editor %F", "its own command not back"
# Lutris open normally: its own command, and migrate leaves it so (it rewrites only minimised ones' quiet start)
ds.startup_add("net.lutris.Lutris.desktop", False)
os.remove(f"{ds.CONFIG}/.startup-moved")
ds.migrate({}, False)
assert ds.desktop_entry(f"{mine}/net.lutris.Lutris.desktop")["Exec"] == "lutris %U", "migrate made Lutris quiet again"
# An app's own entry (no launcher, its own autostart file): its mode switches from that file
open(f"{mine}/own-tray.desktop", "w").write("[Desktop Entry]\nType=Application\nName=Own\nExec=own --tray\nIcon=own\n")
assert listed()["own-tray.desktop"]["type"] == "startup" and ds.autostart_mode("own-tray.desktop") == "normal"
ds.startup_add("own-tray.desktop", True)
ds.startup_add("own-tray.desktop", False)
assert ds.desktop_entry(f"{mine}/own-tray.desktop")["Exec"] == "own --tray", open(f"{mine}/own-tray.desktop").read()
# Removed: gone from the list (and from your folder, one added here)
ds.autostart_set("editor.desktop", False)
assert "editor.desktop" not in listed() and not os.path.exists(f"{mine}/editor.desktop"), "a removed app still listed"
assert ds.check("autostart.x", {"type": "startup"}, "removed") is None and ds.check("autostart.x", {"type": "startup"}, True)
try:
    ds.startup_add("../hello.desktop")
    raise AssertionError("a path taken as an app")
except SystemExit:
    pass
P
echo "ok dots-settings-autostart"
