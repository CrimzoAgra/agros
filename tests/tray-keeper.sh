#!/usr/bin/env bash
# tray-keeper's Spotify running only when it's yours: with several users logged in, another's Spotify (pgrep sees every
# user's) read as yours had your next Spotify window sent to the silent workspace when the tray went away
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
# pgrep: a Spotify of $SPOTIFY_UID's running (another user's unless it's this one's)
# shellcheck disable=SC2016  # (expanded by the stand-in)
printf '#!/bin/bash\necho "$*" >>%s/pgrep\n[[ " $* " == *" com.spotify.Client "* ]] || exit 1\nif [[ " $* " == *" -u "* ]]; then [[ " $* " == *" -u $SPOTIFY_UID "* ]]; fi\n' \
    "$t" >"$t/bin/pgrep"
chmod +x "$t/bin/pgrep"
# running(): the module loaded with Gio and GLib stand-ins (no D-Bus here), what it says printed
check() {
    PATH=$t/bin:$PATH SPOTIFY_UID=$1 python3 -I - "$here/.local/bin/tray-keeper" <<'P'
import importlib.machinery, importlib.util, sys, types
repo = types.ModuleType("gi.repository")
repo.Gio, repo.GLib = types.SimpleNamespace(), types.SimpleNamespace(MainLoop=lambda: None)
sys.modules["gi"], sys.modules["gi.repository"] = types.ModuleType("gi"), repo
loader = importlib.machinery.SourceFileLoader("tk", sys.argv[1])
tk = importlib.util.module_from_spec(importlib.util.spec_from_loader("tk", loader))
loader.exec_module(tk)
print(tk.running())
P
}
[[ $(check "$(id -u)") == True ]] || fail "your own Spotify not seen running: $(cat "$t/pgrep")"
[[ $(check 99999) == False ]] || fail "another user's Spotify read as yours: $(cat "$t/pgrep")"
echo "ok tray-keeper"
