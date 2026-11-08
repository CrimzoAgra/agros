#!/usr/bin/env bash
# Run from an SSH login or a text console (no HYPRLAND_INSTANCE_SIGNATURE or WAYLAND_DISPLAY), the scripts that talk to
# Hyprland name it (its first one): caelestia-restart has Hyprland run it (from there the shell was killed and the new
# one couldn't start), dots-settings' reload reaches it, dotfiles-check sees its config errors and title bar plugin
# (it said the plugin wasn't loaded), and the desktop step's Caelestia CLI writes the borders' colours for its Lua config
set -euo pipefail
. "$(dirname "$0")/lib.sh"
export log=$t/calls HOME=$t/home XDG_STATE_HOME=''
mkdir -p "$t/bin" "$HOME/.local/bin" "$HOME/.local/state"
# hyprctl as the real one: with no instance named or in the environment it fails (but for its list of them)
cat >"$t/bin/hyprctl" <<'EOS'
#!/bin/sh
case $1 in -i | --instance) shift 2 ;; instances) ;; *) [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || { echo "HYPRLAND_INSTANCE_SIGNATURE not set!"; exit 1; } ;; esac
echo "hyprctl $*" >>"$log"
case $1 in
instances) echo '[{"instance": "first"}]' ;;
configerrors) echo "broken.lua:1: oops" ;;
plugin) echo '[{"name": "hyprbars"}]' ;;
dispatch) echo ok ;;
esac
EOS
printf '#!/bin/sh\necho "qs $*" >>"$log"\n' >"$t/bin/qs"
printf '#!/bin/sh\necho "caelestia $* for ${HYPRLAND_INSTANCE_SIGNATURE:-none}" >>"$log"\n' >"$t/bin/caelestia"
# (Hyprland's own check of its config, dotfiles-check's: fine, so it goes by hyprctl's list)
printf '#!/bin/sh\necho config ok\n' >"$t/bin/Hyprland"
chmod +x "$t/bin/"*
export PATH=$t/bin:$PATH
outside=(env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY)

"${outside[@]}" "$here/.local/bin/caelestia-restart" >/dev/null 2>&1 || true
grep -q '^hyprctl dispatch .*caelestia-restart' "$log" || fail "Hyprland not asked to restart Caelestia: $(cat "$log")"
grep -q '^qs ' "$log" && fail "Caelestia restarted from outside the desktop: $(cat "$log")"

: >"$log"
"${outside[@]}" python3 -I - "$here" <<'P'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ds", f"{sys.argv[1]}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.apply("hypr")
P
for _ in $(seq 50); do grep -q '^hyprctl reload' "$log" && break; sleep 0.1; done
grep -q '^hyprctl reload' "$log" || fail "dots-settings' reload didn't reach Hyprland: $(cat "$log")"

out=$("${outside[@]}" "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"broken.lua:1: oops"* ]] || fail "Hyprland's config errors not seen: $out"
[[ $out == *"Title bar plugin not loaded"* ]] && fail "the loaded title bar plugin said not loaded: $out"

: >"$log"
mkdir -p "$HOME/Pictures/Wallpapers" && : >"$HOME/Pictures/Wallpapers/wallpaper.jpg"
printf '#!/bin/sh\n' >"$HOME/.local/bin/caelestia-overlay" && chmod +x "$HOME/.local/bin/caelestia-overlay"
"${outside[@]}" bash -c \
    'source "$1/.local/bin/agros-welcome"; caelestia_setup' _ "$here" >/dev/null 2>&1 </dev/null
grep -q '^caelestia scheme set -n dynamic for first$' "$log" || fail "the colours not set for Hyprland: $(cat "$log")"
echo "ok outside-desktop"
