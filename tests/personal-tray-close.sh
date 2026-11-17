#!/usr/bin/env bash
# agros-personal's restore with Lutris and Proton VPN in their tray (both start so at login, user/apps.lua): closed for
# it (no terminal to ask in), then the restore goes on; Lutris with a game's window (a process it started) left open,
# and the restore refused; Hyprland not reachable to tell, both left open. VSCodium found open by its command, either
# build's. (Lutris's and Proton VPN's processes stand-ins, found by a pgrep stand-in: yours are never touched)
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
mkdir -p "$t/bin"
cat >"$t/bin/pgrep" <<P
#!/bin/sh
case "\$*" in
    *lutris*) cat "$t/lutris.pid" 2>/dev/null ;;
    *protonvpn-app*) cat "$t/proton.pid" 2>/dev/null ;;
    *) exit 1 ;;
esac
P
printf '#!/bin/sh\ncat "%s/clients"\n' "$t" >"$t/bin/hyprctl"
chmod +x "$t/bin/pgrep" "$t/bin/hyprctl"
pids=()
on_exit 'kill "${pids[@]}"'
# start <lutris|proton> [game]: a stand-in, not this test's child (closed, it's gone at once, not left a zombie until
# reaped); with a game: a process it started
start() {
    local inner='exec sleep 300'
    rm -f "$t/game.pid"
    # shellcheck disable=SC2016  # (the inner shell's)
    [[ ${2-} ]] && inner='sleep 300 & echo $! >"$0"; wait'
    bash -c 'bash -c "$1" "$2" >/dev/null 2>&1 </dev/null & echo $!' _ "$inner" "$t/game.pid" >"$t/$1.pid"
    pids+=("$(cat "$t/$1.pid")")
    if [[ ${2-} ]]; then
        for _ in {1..50}; do [[ -s $t/game.pid ]] && break; sleep 0.1; done
        pids+=("$(cat "$t/game.pid")")
    fi
}
alive() { kill -0 "$(cat "$t/$1.pid")" 2>/dev/null; }
close() { PATH=$t/bin:$PATH bash -c 'source "$1"; personal_close_tray "${@:2}"' _ "$here/.local/bin/agros-personal" "$@" </dev/null; }

# In their tray (no window): both closed, said
start lutris; start proton; echo '[{"pid": 1}, {"pid": 999999999}]' >"$t/clients"
out=$(close lutris protonvpn-app equibop) || fail "closing them failed: $out"
! alive lutris && ! alive proton || fail "apps in their tray only left open"
[[ $out == "Lutris and Proton VPN closed"* ]] || fail "their closing not said: $out"
# Lutris with a game's window: left open (Proton VPN, in its tray, closed)
start lutris game; g=$(cat "$t/game.pid"); start proton; echo "[{\"pid\": $g}]" >"$t/clients"
close lutris protonvpn-app >/dev/null || fail "closing them failed"
alive lutris || fail "Lutris closed with a game of its open"
alive proton && fail "Proton VPN, in its tray, left open beside Lutris with a game"
# Hyprland not there to ask: left open
start proton; rm "$t/clients"
close protonvpn-app >/dev/null || fail "no Hyprland: failed"
alive proton || fail "Proton VPN closed with no Hyprland to tell whether it has a window"

# The restore: what's still open after closing them refused; what closed lets it go on (to the file: none here)
restore() {
    HOME=$t PATH=$t/bin:$PATH bash -c 'source "$1"; dir=$2 closes=$3
        personal_claude_open() { :; }
        personal_open() { [[ -e $dir/closed ]] || echo lutris; }
        personal_close_tray() { [[ -z $closes ]] || : >"$dir/closed"; }
        personal_restore "$dir/none.gpg"' _ "$here/.local/bin/agros-personal" "$t" "${1-}" </dev/null 2>&1
}
out=$(restore) && fail "the restore went on with Lutris open"
[[ $out == "Close these first"*lutris* ]] || fail "Lutris left open not said: $out"
out=$(restore closes) && fail "a file that isn't there read"
[[ $out != *"Close these first"* ]] || fail "the restore refused after closing them: $out"

# VSCodium: Arch's (Electron on /usr/lib/vscodium) and the AUR's (codium) found, nothing else of that name
rm "$t/bin/pgrep"
for cmd in /usr/lib/vscodium/codium /opt/vscodium-bin/codium codium-notes; do
    bash -c 'exec -a "$1" sleep 300' _ "$cmd" &
    p=$!; pids+=("$p")
    for _ in {1..50}; do [[ $(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null) == "$cmd "* ]] && break; sleep 0.1; done
    found=$(bash -c 'source "$1"; personal_pids codium' _ "$here/.local/bin/agros-personal" </dev/null) || found=
    if [[ $cmd == codium-notes ]]; then
        grep -qx "$p" <<<"$found" && fail "$cmd taken for VSCodium"
    else
        grep -qx "$p" <<<"$found" || fail "VSCodium run as $cmd not found"
    fi
done
echo "ok personal-tray-close"
