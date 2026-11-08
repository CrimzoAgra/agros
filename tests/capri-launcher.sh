#!/usr/bin/env bash
# ~/.local/bin/capri: her build started from its folder, through XWayland on Hyprland, its output in ~/.cache/capri.log,
# which is moved to capri.log.1 once past 5 MB (each start adds to it); $CAPRI_RUN run instead when set; not installed: said
set -uo pipefail
. "$(dirname "$0")/lib.sh"
export HOME="$t/ho me" XDG_DATA_HOME='' XDG_CACHE_HOME='' CAPRI_RUN=''
out=$(HYPRLAND_INSTANCE_SIGNATURE='' "$here/.local/bin/capri" 2>&1) && fail "started with her not installed"
[[ $out == *"isn't installed"* ]] || fail "not installed not said: $out"
b="$HOME/.local/share/capri/abc1234"
mkdir -p "$b/node_modules/.bin"
ln -s abc1234 "$HOME/.local/share/capri/current"
printf '#!/bin/sh\necho "started in $(pwd -P) with: $*"\n' >"$b/node_modules/.bin/electron"
chmod +x "$b/node_modules/.bin/electron"
log="$HOME/.cache/capri.log"
HYPRLAND_INSTANCE_SIGNATURE=x "$here/.local/bin/capri" --hidden || fail "she didn't start"
grep -qx "started in $b with: . --ignore-gpu-blocklist --ozone-platform=x11 --hidden" "$log" ||
    fail "not started from her build through XWayland: $(cat "$log")"
# Past 5 MB: moved aside at her next start, the new log begun
head -c 6000000 /dev/zero >"$log"
HYPRLAND_INSTANCE_SIGNATURE='' "$here/.local/bin/capri" || fail "she didn't start"
[[ $(stat -c %s "$log.1") == 6000000 && $(wc -l <"$log") == 1 ]] || fail "the log not moved aside past 5 MB"
grep -qx "started in $b with: . --ignore-gpu-blocklist" "$log" || fail "outside Hyprland, not started as she is: $(cat "$log")"
# A small one kept as it is
HYPRLAND_INSTANCE_SIGNATURE='' "$here/.local/bin/capri"
[[ $(wc -l <"$log") == 2 ]] || fail "a small log moved aside"
# $CAPRI_RUN: that script instead, with her arguments
printf '#!/bin/sh\necho "mine: $*"\n' >"$t/run"; chmod +x "$t/run"
[[ $(CAPRI_RUN=$t/run "$here/.local/bin/capri" --hidden) == "mine: --hidden" ]] || fail "\$CAPRI_RUN not run"
echo "ok capri-launcher"
