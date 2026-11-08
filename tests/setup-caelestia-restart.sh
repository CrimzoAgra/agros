#!/usr/bin/env bash
# The desktop step run from an SSH login or a text console (no HYPRLAND_INSTANCE_SIGNATURE) still restarts the running
# Caelestia onto the overlay it rebuilt, through the desktop's Hyprland: hyprctl alone doesn't know it there, and the
# restart failed with nothing said (the shell kept the old overlay until the next login)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export HOME=$t/home log=$t/calls
mkdir -p "$HOME/.local/bin" "$HOME/.local/state" "$t/bin"
touch "$HOME/.local/state/dotfiles-wallpaper-set"  # (wallpaper already set: not part of this)
printf '#!/bin/sh\n' >"$HOME/.local/bin/caelestia-overlay"
# Stand-ins: Caelestia running (Quickshell's list), and hyprctl as the real one: with no instance named or in the
# environment it fails
printf '#!/bin/sh\necho "  Config path: %s/.config/quickshell/caelestia/shell.qml"\n' "$HOME" >"$t/bin/qs"
cat >"$t/bin/hyprctl" <<'EOS'
#!/bin/sh
case $1 in -i | --instance) ;; *) [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || { echo "HYPRLAND_INSTANCE_SIGNATURE not set!"; exit 1; } ;; esac
echo "hyprctl $*" >>"$log"
EOS
chmod +x "$t/bin/"* "$HOME/.local/bin/"*
export PATH=$t/bin:$PATH

out=$(env -u HYPRLAND_INSTANCE_SIGNATURE repo="$here" yes=true bash -c \
    'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; caelestia_setup' _ "$here" 2>&1 </dev/null)
grep -q 'caelestia-restart' "$log" 2>/dev/null || fail "Caelestia not restarted from outside the desktop: $out"
[[ $out == *"Caelestia restarted"* ]] || fail "the restart not said: $out"
# Inside the desktop: its own Hyprland
: >"$log"
HYPRLAND_INSTANCE_SIGNATURE=mine repo="$here" yes=true bash -c \
    'source "$1/setup/lib.sh"; source "$1/setup/modules/60-desktop.sh"; caelestia_setup' _ "$here" >/dev/null 2>&1 </dev/null
grep -q '^hyprctl -i mine dispatch' "$log" || fail "not the desktop's own Hyprland: $(cat "$log")"
echo "ok setup-caelestia-restart"
