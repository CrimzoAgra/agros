#!/usr/bin/env bash
# game-focus's placement: a fullscreen game sharing its workspace moves to a free one in tiling mode only, and
# switching from floating to tiling moves one that stayed put; on a second, scaled screen too
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/.local/state"
HOME=$t python3 -I - "$here/.local/bin/game-focus" "$t" <<'P'
import importlib.machinery, importlib.util, json, sys
path, t = sys.argv[1:]
loader = importlib.machinery.SourceFileLoader("gf", path)
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
calls = []
def hypr(*a):
    if a[:1] == ("monitors",):
        return json.dumps([{"id": 0, "width": 1920, "height": 1080, "scale": 1}])
    calls.append(a)
    return ""
gf.hypr = hypr
game = {"address": "0xg", "class": "steam_app_1", "pid": -1, "workspace": {"id": 1}, "monitor": 0, "size": [1920, 1080], "fullscreen": 2}
other = {"address": "0xo", "class": "foot", "pid": -1, "workspace": {"id": 1}, "monitor": 0, "size": [800, 600], "fullscreen": 0}
def mode(m):
    open(f"{t}/.local/state/window-mode", "w").write(m + "\n")
def fail(msg):
    print(f"FAIL: {msg}: {calls}"); sys.exit(1)
moved = lambda: any("hl.dsp.window.move" in " ".join(c) for c in calls)
mode("floating")
gf.place_games([game, other], "0xg")
if moved(): fail("a game moved in floating mode")
mode("tiling")
gf.place_games([game, other], "0xg")
if not moved(): fail("switching to tiling didn't move the game sharing its workspace")
calls.clear()
gf.place_games([game, other], "0xg")
if moved(): fail("a game moved twice (moved back by hand, it stays)")
mode("floating"); gf.place_games([game, other], "0xg"); mode("tiling")
gf.place_games([game, other], "0xg")
if not moved(): fail("floating then tiling again didn't move it")
# A borderless game covering a rotated (portrait) screen counts as fullscreen too
gf.hypr = lambda *a: json.dumps([{"id": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 1}]) if a[:1] == ("monitors",) else calls.append(a) or ""
calls.clear()
tall = dict(game, address="0xt", size=[1080, 1920], fullscreen=0)
gf.place_games([tall, other], "0xt")
if not moved(): fail("a borderless game on a portrait screen wasn't moved")
# A workspace whose only window is minimised isn't free (the window comes back there, next to the game)
gf.hypr = hypr
calls.clear()
mini = {"address": "0xm", "class": "foot", "pid": -1, "workspace": {"id": -98, "name": "special:minimised-2"}, "monitor": 0, "size": [800, 600], "fullscreen": 0}
gf.place_games([dict(game, address="0xh"), other, mini], "0xh")
if not any("workspace = 3," in " ".join(c) for c in calls): fail("moved onto a workspace holding a minimised window")
# A second screen (its workspaces 11-20), scaled 1.25: a borderless game covering it moves to that screen's free column
gf.hypr = lambda *a: json.dumps([{"id": 0, "width": 1920, "height": 1080, "scale": 1},
                                 {"id": 1, "width": 2560, "height": 1440, "scale": 1.25}]) if a[:1] == ("monitors",) else calls.append(a) or ""
calls.clear()
second = dict(game, address="0xs", workspace={"id": 11}, monitor=1, size=[2048, 1152], fullscreen=0)
gf.place_games([second, dict(other, workspace={"id": 11}, monitor=1), dict(other, address="0xp", workspace={"id": 2})], "0xs")
if not any("workspace = 13," in " ".join(c) for c in calls): fail("not moved to the second screen's free workspace")
if ("eval", "dots.goto_workspace(3)") not in calls: fail("not followed to the free column")
# A pinned window (Capri, listed on the workspace its screen shows) doesn't share the game's: a game alone stays
gf.hypr = hypr
calls.clear()
capri = dict(other, address="0xc", pinned=True)
gf.place_games([dict(game, address="0xa"), capri], "0xa")
if moved(): fail("a game alone but for a pinned window moved")
# Only the game you're on: one that came to cover its screen while you were elsewhere stays (else it pulled you back)
calls.clear()
gf.place_games([dict(game, address="0xb"), other], "0xo")
if moved(): fail("a game you're not on moved")
print("ok game-focus-place")
P
