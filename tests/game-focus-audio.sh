#!/usr/bin/env bash
# A game you're not looking at is muted; an app it started with a window of its own (a browser opening a link: it
# inherits the game's id) isn't, nor is the game unmuted for having Steam's window above it; a Flatpak game's sound
# (its sandbox's pid) is muted too, but not a pid two games' sandboxes both have
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cleanup() { kill $(cat "$t"/{helper,sound,windowless,browser,game} 2>/dev/null) 2>/dev/null || true; pkill -P $$ 2>/dev/null || true; kill -KILL $(cat "$t/unshare" 2>/dev/null) 2>/dev/null || true; rm -rf "$t"; }  # (grandchildren too)
trap cleanup EXIT
export T=$t
# The game (from Steam's games folder), its own sound process, and the browser it started with that browser's sound helper
SteamGameId=4242 bash -c 'exec -a "/s/steamapps/common/G/game" bash -c '\''
    (exec -a librewolf bash -c "sleep 60 & echo \$! >\"\$T/helper\"; echo \$\$ >\"\$T/browser\"; wait") &
    sleep 60 & echo $! >"$T/sound"; echo $$ >"$T/game"; wait'\''' >/dev/null 2>&1 &
# A Flatpak game: in a PID namespace of its own, its sound process known there by its own pid ($T/nspid)
# (--kill-child: the namespace ends with unshare, killed by cleanup: both ignore a TERM)
SteamGameId=5151 unshare -Urpf --kill-child bash -c 'readlink /proc/self/ns/pid >"$T/ns"; sleep 60 & echo $! >"$T/nspid"; wait' >/dev/null 2>&1 &
echo $! >"$t/unshare"
for _ in $(seq 50); do [[ -s $t/helper && -s $t/sound && -s $t/nspid ]] && break; sleep 0.1; done
python3 -I - "$here/.local/bin/game-focus" "$t" <<'P'
import importlib.machinery, importlib.util, json, os, sys
path, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("gf", path)
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
import atexit, subprocess
# A game process with no window, its parent Steam (this process, with Steam's window 0x3): still the game's sound
windowless = subprocess.Popen(["sleep", "60"], env={**os.environ, "SteamGameId": "4242"})
atexit.register(windowless.kill)
open(f"{t}/windowless", "w").write(str(windowless.pid))
pid = {n: int(open(f"{t}/{n}").read()) for n in ("game", "sound", "browser", "helper", "windowless", "nspid")}
gf.setting = lambda k: k == "games.audio_focus"
clients = [{"address": "0x1", "pid": pid["game"], "class": "game", "workspace": {"id": 1}, "tags": []},
           {"address": "0x2", "pid": pid["browser"], "class": "librewolf", "workspace": {"id": 2}, "tags": []},
           {"address": "0x3", "pid": os.getpid(), "class": "steam", "workspace": {"id": 3}, "tags": []},
           {"address": "0x4", "pid": 1, "class": "steam_app_5151", "workspace": {"id": 4}, "tags": []}]
gf.hypr = lambda *a: json.dumps(clients if a[0] == "clients" else clients[1])  # the browser focused
streams = [{"index": i, "client": 0, "mute": False, "properties": {"application.process.id": str(pid[n])}}
           for i, n in enumerate(("sound", "helper", "windowless", "nspid", "nspid"))]
# Stream 3 a Flatpak's (its sandbox's bwrapinfo.json names its PID namespace; pipewire.access, as a native PipeWire
# stream's client has, not only a Pulse one's pipewire.client.access); 4 a host app's that has the same pid
streams[3]["properties"] |= {"pipewire.access": "flatpak", "pipewire.access.portal.instance_id": "77"}
os.makedirs(f"{t}/run/.flatpak/77")
ns = open(f"{t}/ns").read().strip()
json.dump({"pid-namespace": int(ns[5:-1])}, open(f"{t}/run/.flatpak/77/bwrapinfo.json", "w"))
os.environ["XDG_RUNTIME_DIR"] = f"{t}/run"
os.environ["PATH"] = "/nonexistent"  # no pactl (no sound stack): no streams, not an error
if gf.pactl("sink-inputs") != "[]": sys.exit("FAIL: no pactl wasn't taken as no streams")
gf.pactl = lambda kind: json.dumps(streams if kind == "sink-inputs" else [])
muted = []
gf.subprocess.run = lambda cmd, **kw: muted.append(int(cmd[2])) if cmd[:2] == ["pactl", "set-sink-input-mute"] and cmd[3] == "1" else None
if not gf._update(): sys.exit("FAIL: the game wasn't seen")
if 1 in muted: sys.exit("FAIL: the browser the game started was muted")
if 0 not in muted: sys.exit("FAIL: the game's sound wasn't muted")
if 2 not in muted: sys.exit("FAIL: a game process under Steam's window wasn't muted")
if 3 not in muted: sys.exit("FAIL: the Flatpak game's sound (its sandbox's pid) wasn't muted")
if 4 in muted: sys.exit("FAIL: a host app's sound with a pid a sandbox has too was taken as that game's")
# A second game's sandbox with a process of that same pid: no telling whose sound it is
import subprocess, time
other = subprocess.Popen(["unshare", "-Urpf", "--kill-child", "bash", "-c", f"readlink /proc/self/ns/pid >/dev/null; sleep 60 & echo $! >{t}/nspid2; wait"],  # (as the first: the same pid)
                         env={**os.environ, "PATH": "/usr/bin", "SteamGameId": "6161"})
for _ in range(50):
    if os.path.exists(f"{t}/nspid2") and os.path.getsize(f"{t}/nspid2"):
        break
    time.sleep(0.1)
same = int(open(f"{t}/nspid2").read()) == pid["nspid"]
found = gf.host_pid(pid["nspid"])
own = gf.host_pid(pid["nspid"], ns)  # in its own sandbox only: still found
other.kill(); other.wait()
if not same: sys.exit("FAIL: the second sandbox's process didn't get the same pid")
if found != -1: sys.exit(f"FAIL: a pid two games' sandboxes have was taken as one's ({found})")
if own <= 0: sys.exit("FAIL: the game's process not found in its own sandbox beside another's")
print("ok game-focus-audio")
P
