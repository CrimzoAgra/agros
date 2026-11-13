#!/usr/bin/env bash
# dots-settings' ways of applying a change ("hypr", "caelestia") with a home folder whose path has a space and shell
# characters: the scripts there run, and nothing of the path runs as a command
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
# shellcheck disable=SC2016  # (a literal "$(...)" in the folder's name, on purpose)
home="$t/my home \$(touch $t/injected); x"
mkdir -p "$home/.local/bin" "$t/bin"
for s in after-games caelestia-overlay caelestia-restart; do
    printf '#!/bin/sh\necho %s "$@" >>"%s/ran"\n' "$s" "$t" >"$home/.local/bin/$s"
done
printf '#!/bin/sh\necho "hyprctl $*" >>"%s/ran"\n' "$t" >"$t/bin/hyprctl"
chmod +x "$home/.local/bin/"* "$t/bin/hyprctl"
HYPRLAND_INSTANCE_SIGNATURE='' PATH=$t/bin:$PATH python3 -I - "$here" "$home" <<'P' || fail "applying failed"
import importlib.machinery, importlib.util, pwd, subprocess, sys
here, home = sys.argv[1:]
real = pwd.getpwuid
pwd.getpwuid = lambda uid: type("P", (), {"pw_dir": home})()  # (its home: the passwd one, at load)
loader = importlib.machinery.SourceFileLoader("ds", f"{here}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
pwd.getpwuid = real
for how in ("caelestia", "hypr"):
    if subprocess.run(ds.APPLY[how]).returncode != 0:
        sys.exit(f"{how} failed")
P
for _ in {1..50}; do grep -q '^hyprctl' "$t/ran" 2>/dev/null && break; sleep 0.1; done  # (hypr's: in the background)
[[ $(cat "$t/ran" 2>/dev/null) == $'caelestia-restart --rebuild\nafter-games\nhyprctl -i 0 reload' ]] ||
    fail "the scripts in a home with a space didn't run: $(cat "$t/ran" 2>/dev/null)"
[[ ! -e $t/injected ]] || fail "part of the home folder's path ran as a command"
echo "ok dots-settings-apply"
