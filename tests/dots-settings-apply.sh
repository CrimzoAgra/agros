#!/usr/bin/env bash
# dots-settings' ways of applying a change with a home folder whose path has a space and shell characters: the scripts
# there run, and nothing of the path runs as a command ("caelestia"); "hypr": hypr-reload, after any game (after-games'
# look at the windows first)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2016  # (a literal "$(...)" in the folder's name, on purpose)
home="$t/my home \$(touch $t/injected); x"
mkdir -p "$home/.local/bin" "$t/bin"
# (the scripts it runs are the ones beside it: all of them there, the two that would rebuild stubbed)
cp -r "$here/.local/bin/." "$home/.local/bin/"
for s in caelestia-overlay caelestia-restart; do
    printf '#!/bin/sh\necho %s "$@" >>"%s/ran"\n' "$s" "$t" >"$home/.local/bin/$s"
done
printf '#!/bin/sh\necho "hyprctl $*" >>"%s/ran"\n' "$t" >"$t/bin/hyprctl"
chmod +x "$home/.local/bin/caelestia-"* "$t/bin/hyprctl"
HYPRLAND_INSTANCE_SIGNATURE='' PATH=$t/bin:$PATH python3 -I - "$here" "$home" <<'P' || fail "applying failed"
import importlib.machinery, importlib.util, pwd, subprocess, sys
here, home = sys.argv[1:]
real = pwd.getpwuid
pwd.getpwuid = lambda uid: type("P", (), {"pw_dir": home})()  # (its home: the passwd one, at load)
loader = importlib.machinery.SourceFileLoader("ds", f"{home}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
pwd.getpwuid = real
for how in ("caelestia", "hypr"):
    if subprocess.run(ds.APPLY[how]).returncode != 0:
        sys.exit(f"{how} failed")
P
for _ in {1..50}; do grep -q 'reload$' "$t/ran" 2>/dev/null && break; sleep 0.1; done  # (hypr's: in the background)
[[ $(cat "$t/ran" 2>/dev/null) == $'caelestia-restart --rebuild\nhyprctl -i 0 clients -j\nhyprctl -i 0 reload' ]] ||
    fail "the scripts in a home with a space didn't run: $(cat "$t/ran" 2>/dev/null)"
[[ ! -e $t/injected ]] || fail "part of the home folder's path ran as a command"

# A game open: "deferred" said to the Settings app, one notification and one reload once it closes for two requests
: >"$t/ran"
printf '#!/bin/sh\n[ ! -e "%s/closed" ]\n' "$t" >"$home/.local/bin/game-focus"
printf '#!/bin/sh\nuntil [ -e "%s/closed" ]; do sleep 0.1; done\n' "$t" >"$home/.local/bin/after-games"
printf '#!/bin/sh\necho "notify $*" >>"%s/ran"\n' "$t" >"$t/bin/notify-send"
chmod +x "$home/.local/bin/game-focus" "$home/.local/bin/after-games" "$t/bin/notify-send"
out=$(HYPRLAND_INSTANCE_SIGNATURE='' PATH=$t/bin:$PATH "$home/.local/bin/dots-settings" apply hypr) || fail "apply failed"
[[ $out == deferred ]] || fail "a deferred apply not said: $out"
# (a second one leaves it to the waiting one: said by its exit, 3, as the screens' reload waits for that one then)
rc=0; HYPRLAND_INSTANCE_SIGNATURE='' PATH=$t/bin:$PATH "$home/.local/bin/hypr-reload" || rc=$?
[[ $rc == 3 ]] || fail "a reload left to the one waiting for the game not said by exit 3: $rc"
for _ in {1..50}; do grep -q '^notify' "$t/ran" && break; sleep 0.1; done
[[ $(grep -c '^notify .*Applied once your game closes' "$t/ran") == 1 ]] || fail "not said once: $(cat "$t/ran")"
grep -q reload "$t/ran" && fail "reloaded during the game"
touch "$t/closed"
for _ in {1..50}; do grep -q 'reload$' "$t/ran" && break; sleep 0.1; done
sleep 0.5
[[ $(grep -c 'reload$' "$t/ran") == 1 ]] || fail "not one reload once the game closed: $(cat "$t/ran")"
echo "ok dots-settings-apply"
