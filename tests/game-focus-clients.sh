#!/usr/bin/env bash
# Closing a game closes its clients: the store launcher left in its Wine prefix (not while something of the prefix has
# a window on a workspace; its own minimised window, tagged like a game under Proton, doesn't count), and Steam when it's only in its tray
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cleanup() {  # (also when a check failed)
    local p
    for p in ${reaper:-} ${busy:-} ${writer:-} ${piper:-}; do pkill -P "$p" 2>/dev/null || true; done
    kill ${busy:-} ${writer:-} ${piper:-} ${l1:-} ${h1:-} ${l2:-} ${h2:-} ${reaper:-} 2>/dev/null || true
    rm -rf "$t" "${disk:-}"
}
trap cleanup EXIT
mkdir -p "$t/pfx"
launch() { WINEPREFIX=$t/pfx bash -c 'exec -a "C:\\EA\\EADesktop.exe" sleep 60' >/dev/null 2>&1 & echo $!; }
helper() { WINEPREFIX=$t/pfx bash -c 'exec -a "QtWebEngineProcess.exe" sleep 60' >/dev/null 2>&1 & echo $!; }
l1=$(launch); h1=$(helper); l2=$(launch); h2=$(helper)
# A Steam game that didn't exit: Steam's reaper with the game under it
exec -a "reaper" bash -c 'sleep 60 & wait' SteamLaunch AppId=4242 -- >/dev/null 2>&1 &
reaper=$!
# Three more with no window under their reapers: one spinning a CPU loop (hung), one spinning on a pipe (hung too: as
# one on wineserver's, no disk), one writing to disk (working: a save, an update). On a real disk, not /tmp's tmpfs
exec -a "reaper" bash -c 'while :; do :; done & wait' SteamLaunch AppId=4343 -- >/dev/null 2>&1 &
busy=$!
exec -a "reaper" bash -c 'yes | cat >/dev/null & wait' SteamLaunch AppId=4646 -- >/dev/null 2>&1 &
piper=$!
disk=$(mktemp -d /var/tmp/game-focus-test.XXXXXX)
printf '%s\n' 'import os, sys, time' 'while True:' '    with open(sys.argv[1], "wb") as f:' \
    '        f.write(b"x" * (4 << 20)); f.flush(); os.fsync(f.fileno())' '    time.sleep(0.1)' >"$disk/writer.py"
exec -a "reaper" bash -c 'python3 "$0/writer.py" "$0/f" & wait' "$disk" SteamLaunch AppId=4444 -- >/dev/null 2>&1 &
writer=$!
sleep 0.3
# (HOME: setting() reads your settings, which could have games.close_clients off)
HOME=$t python3 -I - "$here/.local/bin/game-focus" "$t" "$l1 $h1" "$l2 $h2" "$reaper" "$busy" "$writer" "$piper" <<'P'
import importlib.machinery, importlib.util, json, os, sys, time
path, t, first, second, reaper, busy, writer, piper = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("gf", path)
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
gf.SETTINGS = {}
gf.BUSY_SAMPLE = 1  # (watched 5 s: 1 here)
launching = False
gf.steam_game_running = lambda: launching
steam_up = True
gf.steam_running = lambda: steam_up
clients = []
gf.hypr = lambda *a: json.dumps(clients) if a[:1] == ("clients",) else ""
started = []
real_popen = gf.subprocess.Popen
gf.subprocess.Popen = lambda cmd, **kw: started.append(cmd) if cmd[0] in ("steam", "flatpak") else real_popen(cmd, **kw)
def fail(msg):
    print(f"FAIL: {msg}"); sys.exit(1)
def alive(pids):
    time.sleep(0.3)
    return [p for p in map(int, pids.split()) if os.path.exists(f"/proc/{p}") and open(f"/proc/{p}/stat").read().split()[2] != "Z"]
game = {"prefix": os.path.realpath(f"{t}/pfx".encode()), "steam": False}
# The second pair's helper has a window on a workspace: you're using something of that prefix
clients = [{"address": "0x1", "pid": int(second.split()[1]), "class": "x", "workspace": {"id": 1}, "tags": []}]
gf.close_launcher(game)
if len(alive(first)) != 2 or len(alive(second)) != 2: fail("closed a prefix with a window you're using")
# Something else of the prefix minimised (a mod manager in the dock): still in use
clients = [{"address": "0x5", "pid": int(second.split()[1]), "class": "x", "workspace": {"id": -98}, "tags": []}]
gf.close_launcher(game)
if len(alive(first)) != 2: fail("closed a prefix with a minimised app in it")
# The launcher's own window, minimised, with the "game" tag Proton's class gets: not a game keeping it open
clients = [{"address": "0x3", "pid": int(first.split()[0]), "class": "steam_app_default", "workspace": {"id": -98},
            "tags": ["game*"]}]
gf.close_launcher(game)
if alive(first) or alive(second): fail(f"the launcher left in the prefix wasn't closed ({alive(first)} {alive(second)})")
# Steam: no Steam game left, its window not open: shut down
clients = [{"address": "0x2", "pid": 1, "class": "steam", "workspace": {"id": 1}, "tags": []}]
gf.close_steam({"prefix": b"", "steam": True})
if started: fail("Steam closed with its window open")
clients = []
launching = True
gf.close_steam({"prefix": b"", "steam": True})
if started: fail("Steam closed while it was starting another game")
launching = False
gf.close_steam({"prefix": b"", "steam": True})
if started != [["steam", "-shutdown"]]: fail(f"Steam in its tray wasn't closed: {started}")
started.clear()
# Steam's toasts and menus on a workspace (tagged xwl_popup, user/apps.lua) aren't its window
clients = [{"address": "0x6", "pid": 1, "class": "steam", "workspace": {"id": 1}, "tags": ["xwl_popup"]}]
gf.close_steam({"prefix": b"", "steam": True})
if started != [["steam", "-shutdown"]]: fail(f"a Steam toast counted as its window open: {started}")
started.clear()
clients = []
steam_up = False
gf.close_steam({"prefix": b"", "steam": True})
if started: fail("steam -shutdown run with no Steam running (it would start Steam)")
# Flathub's Steam (the same process name, no steam command): shut down through flatpak
steam_up = True
which = gf.shutil.which
gf.shutil.which = lambda name: None
gf.close_steam({"prefix": b"", "steam": True})
gf.shutil.which = which
if started != [["flatpak", "run", "com.valvesoftware.Steam", "-shutdown"]]: fail(f"Flathub's Steam not closed: {started}")
started.clear()
steam_up = False
# What's left of a Steam game with no window: ended (not while a window of it is still there)
timers = []
gf.threading.Timer = lambda *a, **k: timers.append(a[1]) or type("T", (), {"start": lambda self: None, "daemon": True})()
kids = gf.descendants(int(reaper))
if not kids: fail("the test's game process didn't start")
clients = [{"address": "0x4", "pid": kids[0], "class": "steam_app_4242", "workspace": {"id": 1}, "tags": []}]
gf.game_id = lambda c: "4242" if c.get("class") == "steam_app_4242" else ""
gf.end_leftovers({"gid": "4242", "prefix": b"", "steam": True, "proton": True, "reapers": [int(reaper)]})
if not alive(" ".join(map(str, kids))): fail("ended a game that still has its window")
clients = []
# Started again since it closed (a run that wasn't there then): left alone
gf.end_leftovers({"gid": "4242", "prefix": b"", "steam": True, "proton": True, "reapers": []})
if not alive(" ".join(map(str, kids))): fail("ended a copy of the game started after it closed")
# (nothing of that run left, e.g. it ended after Steam's 15 s look: Steam still gets another look)
if timers != [gf.close_steam]: fail(f"Steam wasn't looked at again with nothing left to end: {timers}")
# Another of its windows closed less than two minutes ago: that one's turn, not this
gf.last_closed["4242"] = time.monotonic()
gf.end_leftovers({"gid": "4242", "prefix": b"", "steam": True, "proton": True, "reapers": [int(reaper)]})
if not alive(" ".join(map(str, kids))): fail("ended a game whose last window closed only now")
gf.last_closed.clear()
gf.end_leftovers({"gid": "4242", "prefix": b"", "steam": True, "proton": True, "reapers": [int(reaper)]})
if alive(" ".join(map(str, kids))): fail("a game left running with no window wasn't ended")
# Still working with no window (reading or writing the disk: a save, an update): left running, looked at again later,
# however many looks
gf.HUNG_LOOKS = 3
io_kids = gf.descendants(int(writer))
if not io_kids: fail("the test's working game process didn't start")
for n in range(4):
    timers.clear()
    gf.end_leftovers({"gid": "4444", "prefix": b"", "steam": True, "proton": True, "reapers": [int(writer)]})
    if len(alive(" ".join(map(str, io_kids)))) != len(io_kids): fail(f"ended a game still writing (look {n + 1})")
    if timers != [gf.end_leftovers]: fail(f"a game still working wasn't looked at again later: {timers}")
# CPU with nothing read or written on disk (a thread spinning hung; on a pipe too): looked at again, then closed at the
# HUNG_LOOKS-th look
for gid, root, what in (("4343", busy, "a CPU loop"), ("4646", piper, "a pipe")):
    spin_kids = gf.descendants(int(root))
    if not spin_kids: fail(f"the test's game spinning on {what} didn't start")
    for n in range(gf.HUNG_LOOKS - 1):
        timers.clear()
        gf.end_leftovers({"gid": gid, "prefix": b"", "steam": True, "proton": True, "reapers": [int(root)]})
        if len(alive(" ".join(map(str, spin_kids)))) != len(spin_kids): fail(f"a game spinning on {what} ended at look {n + 1}")
        if timers != [gf.end_leftovers]: fail(f"a game spinning on {what} wasn't looked at again: {timers}")
    timers.clear()
    gf.end_leftovers({"gid": gid, "prefix": b"", "steam": True, "proton": True, "reapers": [int(root)]})
    if alive(" ".join(map(str, spin_kids))): fail(f"a game spinning on {what} with no disk I/O for {gf.HUNG_LOOKS} looks wasn't closed")
    if timers != [gf.close_steam]: fail(f"after closing a hung game, not Steam's look: {timers}")
# One look at a time per game: its windows closing one after another start one look, on the last one's run
for a in ("0xa", "0xb"):
    gf.games_open[a] = {"gid": "5555", "prefix": b"", "steam": False, "proton": True}
timers.clear()
gf.game_closed("0xa"); gf.game_closed("0xb")
if timers.count(gf.end_leftovers) != 1: fail(f"two windows closing started {timers.count(gf.end_leftovers)} looks")
# A setting changed in the Settings app counts at once (not only at the next config reload)
gf.SETTINGS_FILE = f"{t}/settings.json"
gf.load_settings = lambda: setattr(gf, "SETTINGS", json.load(open(gf.SETTINGS_FILE)))
open(gf.SETTINGS_FILE, "w").write('{"games.close_clients": true}')
if not gf.setting("games.close_clients"): fail("setting not read")
time.sleep(0.01)
open(gf.SETTINGS_FILE, "w").write('{"games.close_clients": false}')
if gf.setting("games.close_clients"): fail("a changed setting wasn't read again")
print("ok game-focus-clients")
P
