#!/usr/bin/env bash
# How Lutris starts Steam games: Steam closed, the shader fix first, then Steam in the tray in a scope of its own; Steam
# running, handed the game; Flathub's Steam with no system one; no Steam at all, nothing
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/.local/bin"
stub() { printf '#!/bin/sh\necho "%s $*" >>%s/ran\n%s\n' "$1" "$t" "${2:-}" >"$3/$1"; chmod +x "$3/$1"; }
stub nvidia-shader-fix "" "$t/.local/bin"
stub systemd-run "" "$t/bin"
run() { rm -f "$t/ran"; HOME=$t PATH=$t/bin "$here/.local/bin/steam-start" steam://rungameid/42 || fail "exit $?"; cat "$t/ran" 2>/dev/null; }
[[ -z $(run) ]] || fail "something started with no Steam: $(run)"
stub flatpak "" "$t/bin"
[[ $(run) == $'flatpak info com.valvesoftware.Steam\nflatpak run com.valvesoftware.Steam -silent steam://rungameid/42' ]] ||
    fail "Flathub's Steam: $(run)"
stub steam "" "$t/bin"
stub pgrep "exit 1" "$t/bin"
[[ $(run) == $'pgrep -u '*$' -x steam\nnvidia-shader-fix --install\nsystemd-run --user --scope --quiet --collect --unit=app-steam-'*' steam -silent steam://rungameid/42' ]] ||
    fail "Steam closed: $(run)"
stub pgrep "exit 0" "$t/bin"
[[ $(run) == $'pgrep -u '*$' -x steam\nsteam -silent steam://rungameid/42' ]] || fail "Steam running: $(run)"
echo "ok steam-start"
