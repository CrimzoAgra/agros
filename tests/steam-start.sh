#!/usr/bin/env bash
# How Lutris starts Steam games: Steam closed, the shader fix first, then Steam in the tray in a scope of its own; Steam
# running, handed the game; Flathub's Steam with no system one; no Steam at all, nothing
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin" "$t/.local/bin"
stub() { printf '#!/bin/sh\necho "%s $*" >>%s/ran\n%s\n' "$1" "$t" "${2:-}" >"$3/$1"; chmod +x "$3/$1"; }
stub nvidia-shader-fix "" "$t/.local/bin"
cp "$here/.local/bin/steam-start" "$t/.local/bin/"  # (beside the stub: it runs the shader fix beside itself)
stub systemd-run "" "$t/bin"
# (id the real one: with PATH only $t/bin, steam-start's pgrep got an empty -u, and the test took any)
ln -s "$(command -v id)" "$t/bin/id"
for c in readlink dirname; do ln -s "$(command -v $c)" "$t/bin/$c"; done  # (its own folder: the shader fix beside it)
run() { rm -f "$t/ran"; HOME=$t PATH=$t/bin "$t/.local/bin/steam-start" steam://rungameid/42 || fail "exit $?"; cat "$t/ran" 2>/dev/null; }
[[ -z $(run) ]] || fail "something started with no Steam: $(run)"
stub flatpak "" "$t/bin"
[[ $(run) == $'flatpak info com.valvesoftware.Steam\nflatpak run com.valvesoftware.Steam -silent steam://rungameid/42' ]] ||
    fail "Flathub's Steam: $(run)"
stub steam "" "$t/bin"
stub pgrep "exit 1" "$t/bin"
[[ $(run) == "pgrep -u $(id -u)"$' -x steam\nnvidia-shader-fix --install\nsystemd-run --user --scope --quiet --collect --unit=app-steam-'*' steam -silent steam://rungameid/42' ]] ||
    fail "Steam closed: $(run)"
stub pgrep "exit 0" "$t/bin"
[[ $(run) == "pgrep -u $(id -u)"$' -x steam\nsteam -silent steam://rungameid/42' ]] || fail "Steam running: $(run)"
echo "ok steam-start"
