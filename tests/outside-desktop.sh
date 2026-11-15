#!/usr/bin/env bash
# Run from an SSH login or a text console (no HYPRLAND_INSTANCE_SIGNATURE or WAYLAND_DISPLAY), the scripts that talk to
# Hyprland name it (its first one): caelestia-restart has Hyprland run it (from there the shell was killed and the new
# one couldn't start), dots-settings' reload reaches it, dotfiles-check sees its config errors and title bar plugin
# (it said the plugin wasn't loaded), and the desktop step's Caelestia CLI writes the borders' colours for its Lua config
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
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
grep -q '^hyprctl dispatch .*env CAELESTIA_RESTART_HANDED=1 .*caelestia-restart' "$log" ||
    fail "Hyprland not asked to restart Caelestia (marked as handed over): $(cat "$log")"
grep -q '^qs ' "$log" && fail "Caelestia restarted from outside the desktop: $(cat "$log")"
: >"$log"
# Hyprland's and Wayland's names set by hand, but not the desktop's environment (no XDG_CURRENT_DESKTOP): handed to
# Hyprland too (started from there, the shell had no Qt theme, and drew Papirus-only icons as missing)
env -u XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE=x WAYLAND_DISPLAY=w "$here/.local/bin/caelestia-restart" >/dev/null 2>&1 || true
grep -q '^hyprctl dispatch .*caelestia-restart' "$log" || fail "a restart without the desktop's environment not handed to Hyprland: $(cat "$log")"
grep -q '^qs ' "$log" && fail "Caelestia restarted without the desktop's environment: $(cat "$log")"
# The run Hyprland starts, in a desktop whose XDG_CURRENT_DESKTOP is another name (Hyprland keeps one set before it):
# not handed back again (it went round forever)
: >"$log"
# (its qs as the real one: the running shell listed until it's stopped, none then, the new one once started; started
# through a stand-in systemd-run, there being no user manager here)
mkdir -p "$t/bin2"
cat >"$t/bin2/qs" <<'Q'
#!/bin/sh
echo "qs $*" >>"$log"
case "$1 $2" in
    "kill --pid") echo stopped >"$log.state" ;;
    "-c caelestia") echo started >"$log.state" ;;
    "list --all")
        case $(cat "$log.state" 2>/dev/null) in
            stopped) ;;
            started) printf 'Process ID: 102\nConfig path: /h/.config/quickshell/caelestia/shell.qml\n' ;;
            *) printf 'Process ID: 101\nConfig path: /h/.config/quickshell/caelestia/shell.qml\n' ;;
        esac ;;
esac
Q
printf '#!/bin/sh\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' >"$t/bin2/systemd-run"
chmod +x "$t/bin2/"*
rc=0
PATH=$t/bin2:$PATH env CAELESTIA_RESTART_HANDED=1 XDG_CURRENT_DESKTOP=GNOME HYPRLAND_INSTANCE_SIGNATURE=x WAYLAND_DISPLAY=w \
    timeout 20 "$here/.local/bin/caelestia-restart" >/dev/null 2>&1 </dev/null || rc=$?
grep -q '^hyprctl dispatch .*caelestia-restart' "$log" && fail "the restart Hyprland ran handed back to it again: $(cat "$log")"
{ ((rc == 0)) && grep -q '^qs kill --pid 101$' "$log" && grep -q '^qs -c caelestia -n -d$' "$log"; } ||
    fail "the restart Hyprland ran didn't restart the shell (exit $rc): $(cat "$log")"

: >"$log"
"${outside[@]}" python3 -I - "$here" <<'P'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ds", f"{sys.argv[1]}/.local/bin/dots-settings")
ds = importlib.util.module_from_spec(importlib.util.spec_from_loader("ds", loader))
loader.exec_module(ds)
ds.apply("hypr")
ds.hyprctl("monitors", "all")
P
grep -q '^hyprctl -j monitors all' "$log" || fail "dots-settings' questions (Screens, bind clashes) didn't reach Hyprland: $(cat "$log")"
for _ in $(seq 50); do grep -q '^hyprctl reload' "$log" && break; sleep 0.1; done
grep -q '^hyprctl reload' "$log" || fail "dots-settings' reload didn't reach Hyprland: $(cat "$log")"

out=$("${outside[@]}" "$here/.local/bin/dotfiles-check" 2>&1) || true
[[ $out == *"broken.lua:1: oops"* ]] || fail "Hyprland's config errors not seen: $out"
[[ $out == *"Title bar plugin not loaded"* ]] && fail "the loaded title bar plugin said not loaded: $out"

: >"$log"
# (beside it: the programs it runs are the ones beside itself; the overlay's build stubbed)
cp -r "$here/.local/bin/." "$HOME/.local/bin/"
printf '#!/bin/sh\n[ "$1" = --running ] && exit 1\nexit 0\n' >"$HOME/.local/bin/caelestia-overlay"
"${outside[@]}" bash -c 'source "$HOME/.local/bin/agros-welcome"; caelestia_setup' >/dev/null 2>&1 </dev/null
grep -q '^caelestia scheme set -n dynamic for first$' "$log" || fail "the colours not set for Hyprland: $(cat "$log")"
echo "ok outside-desktop"
