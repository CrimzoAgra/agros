#!/usr/bin/env bash
# game-focus and another account logged in beside yours: its Steam games (their reapers) aren't yours, so they keep
# neither your Steam open in its tray nor your store launcher's prefix running; your own still count
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
out=$(HOME=$t python3 -I - "$here/.local/bin/game-focus" 2>&1 <<'P'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("gf", sys.argv[1])
gf = importlib.util.module_from_spec(importlib.util.spec_from_loader("gf", loader))
loader.exec_module(gf)
# (a process of another account: init's, root's, when this isn't root)
def owner(d):
    try:
        return os.stat(f"/proc/{d}").st_uid
    except OSError:  # (gone meanwhile)
        return os.getuid()
other = next((int(d) for d in filter(str.isdigit, os.listdir("/proc")) if owner(d) != os.getuid()), None)
if other is None:
    print("skip: no other account's process here")
    sys.exit(0)
reapers = set()
gf.cmdline = lambda pid: b"reaper\0SteamLaunch\0AppId=4242\0--\0sleep\0" if pid in reapers else b""
reapers = {other}
if gf.steam_game_running():
    sys.exit("another account's Steam game counted as yours")
if gf.reapers_of("4242"):
    sys.exit("another account's reaper counted as one of your game's")
reapers = {other, os.getpid()}
if not gf.steam_game_running() or gf.reapers_of("4242") != [os.getpid()]:
    sys.exit("your own Steam game not counted")
print("ok")
P
) || fail "$out"
case $out in
    ok) ;;
    skip:*) skipped "${out#skip: }" ;;
    *) fail "$out" ;;
esac
echo "ok game-focus-other-user"
