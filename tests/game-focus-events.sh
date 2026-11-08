#!/usr/bin/env bash
# game-focus against a fake Hyprland event socket: one update per burst of events (not one per chunk), none for a
# window's title change alone, and one within 0.25 s however long events keep coming
set -euo pipefail
. "$(dirname "$0")/lib.sh"
python3 -I - "$here/.local/bin/game-focus" "$t" <<'P'
import importlib.machinery, importlib.util, os, socket, sys, threading, time
path, t = sys.argv[1:]
os.makedirs(f"{t}/hypr/sig")
os.environ.update(XDG_RUNTIME_DIR=t, HYPRLAND_INSTANCE_SIGNATURE="sig")
loader = importlib.machinery.SourceFileLoader("gf", path)
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
updates = []
gf.update = lambda: updates.append(time.monotonic())
gf.watch_x = gf.watch_audio = lambda: None
gf.signal.signal = lambda *a: None
srv = socket.socket(socket.AF_UNIX)
srv.bind(f"{t}/hypr/sig/.socket2.sock")
srv.listen()
threading.Thread(target=gf.main, daemon=True).start()
c, _ = srv.accept()
def fail(msg):
    print(f"FAIL: {msg} (updates: {len(updates)})"); sys.exit(1)
def settle():
    time.sleep(0.4); n = len(updates); updates.clear(); return n
settle()  # the one at connect
for chunk in (b"activewindowv2>>a1\n", b"activewindow>>x,y\n", b"workspacev2>>2,2\n", b"workspace>>2\n"):
    c.sendall(chunk); time.sleep(0.01)
if (n := settle()) != 1: fail(f"an Alt+Tab in 4 chunks made {n} updates, not 1")
c.sendall(b"activewindowv2>>a1\n")
if (n := settle()) != 0: fail(f"the same window again (a title change) made {n} updates")
end = time.monotonic() + 0.6
while time.monotonic() < end:
    c.sendall(b"workspacev2>>3,3\n"); time.sleep(0.02)
updates_during = len(updates)
if updates_during < 2: fail(f"events every 20 ms for 0.6 s starved the update ({updates_during})")
print("ok game-focus-events")
P
